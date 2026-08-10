defmodule Thicket.Federation.RemoteActors do
  @moduledoc "Normalized warm-cache storage and discovery for remote ActivityPub actors."

  import Ecto.Query

  alias Thicket.Federation.{Actor, Fetcher, IRI, RemoteActor, Serializer}
  alias Thicket.Repo

  def get_or_fetch(iri, opts \\ []) do
    with {:ok, iri} <- IRI.parse(iri) do
      case Repo.get_by(RemoteActor, canonical_iri: iri.value) do
        %RemoteActor{} = actor -> maybe_refresh(actor, opts)
        nil -> fetch_and_store(iri, nil, opts)
      end
    end
  end

  def discover_account(username, domain, opts \\ [])
      when is_binary(username) and is_binary(domain) do
    resource = "acct:#{username}@#{String.downcase(domain)}"

    url =
      "https://#{String.downcase(domain)}/.well-known/webfinger?" <>
        URI.encode_query(%{"resource" => resource})

    with {:ok, %{value: document}} <- Fetcher.fetch_json(url, opts),
         {:ok, actor_iri} <- webfinger_actor(document),
         {:ok, actor} <- get_or_fetch(actor_iri, opts) do
      {:ok, actor}
    end
  end

  def touch(%RemoteActor{} = actor) do
    actor
    |> Ecto.Changeset.change(last_accessed_at: DateTime.utc_now(:second))
    |> Repo.update()
  end

  def get_by_key_id(key_id) when is_binary(key_id) do
    Repo.get_by(RemoteActor, public_key_id: key_id)
  end

  def refresh(%RemoteActor{} = actor, opts \\ []) do
    fetch_and_store(IRI.parse!(actor.canonical_iri), actor, opts)
  end

  def evict_stale(now \\ DateTime.utc_now(:second)) do
    cutoff = DateTime.add(now, -retention_days() * 86_400, :second)

    from(actor in RemoteActor,
      where: actor.cache_state == :warm and actor.last_accessed_at < ^cutoff
    )
    |> Repo.update_all(
      set: [
        actor_type: nil,
        preferred_username: nil,
        name: nil,
        summary: nil,
        inbox_iri: nil,
        outbox_iri: nil,
        followers_iri: nil,
        following_iri: nil,
        shared_inbox_iri: nil,
        public_key_id: nil,
        public_key_pem: nil,
        etag: nil,
        last_modified: nil,
        normalized_document: nil,
        cache_state: :cold,
        updated_at: now
      ]
    )
  end

  defp maybe_refresh(%RemoteActor{cache_state: :cold} = actor, opts),
    do: fetch_and_store(IRI.parse!(actor.canonical_iri), actor, opts)

  defp maybe_refresh(%RemoteActor{} = actor, opts) do
    stale_before = DateTime.add(DateTime.utc_now(:second), -freshness_seconds(), :second)

    if DateTime.compare(actor.fetched_at, stale_before) == :lt do
      fetch_and_store(IRI.parse!(actor.canonical_iri), actor, opts)
    else
      touch(actor)
    end
  end

  defp fetch_and_store(%IRI{} = requested_iri, existing, opts) do
    with {:ok, %{value: %Actor{} = actor} = metadata} <-
           Fetcher.fetch_with_metadata(requested_iri.value, opts),
         :ok <- same_authority(requested_iri, actor.id),
         :ok <- complete_actor(actor) do
      now = DateTime.utc_now(:second)

      attrs = %{
        canonical_iri: actor.id.value,
        actor_type: actor.type,
        preferred_username: actor.preferred_username,
        name: actor.name,
        summary: actor.summary,
        inbox_iri: value(actor.inbox),
        outbox_iri: value(actor.outbox),
        followers_iri: value(actor.followers),
        following_iri: value(actor.following),
        shared_inbox_iri: value(actor.shared_inbox),
        public_key_id: actor.public_key && actor.public_key.id.value,
        public_key_pem: actor.public_key && actor.public_key.public_key_pem,
        source_authority: actor.id.host,
        etag: metadata.etag,
        last_modified: metadata.last_modified,
        normalized_document: Serializer.to_map(actor),
        cache_state: :warm,
        fetched_at: now,
        validated_at: now,
        last_accessed_at: now
      }

      (existing || %RemoteActor{})
      |> RemoteActor.changeset(attrs)
      |> Repo.insert_or_update()
    end
  end

  defp same_authority(%IRI{host: host}, %IRI{host: host}), do: :ok
  defp same_authority(_, _), do: {:error, :actor_authority_mismatch}

  defp complete_actor(%Actor{inbox: %IRI{}, public_key: %{public_key_pem: pem}})
       when is_binary(pem),
       do: :ok

  defp complete_actor(_), do: {:error, :incomplete_actor}

  defp webfinger_actor(%{"links" => links}) when is_list(links) do
    links
    |> Enum.find(fn link ->
      is_map(link) and link["rel"] == "self" and
        link["type"] in ["application/activity+json", "application/ld+json"]
    end)
    |> case do
      %{"href" => href} when is_binary(href) -> {:ok, href}
      _ -> {:error, :actor_link_missing}
    end
  end

  defp webfinger_actor(_), do: {:error, :invalid_webfinger}
  defp value(nil), do: nil
  defp value(%IRI{value: value}), do: value

  defp config(key), do: :thicket |> Application.fetch_env!(:federation) |> Keyword.fetch!(key)
  defp retention_days, do: config(:remote_cache_retention_days)
  defp freshness_seconds, do: config(:actor_freshness_seconds)
end
