defmodule Thicket.Federation.Follows do
  @moduledoc "Federated follow state transitions, independent of HTTP delivery."

  import Ecto.Query

  alias Ecto.Multi
  alias Thicket.Federation.{Activity, Deliveries, IRI, RemoteActor, Serializer, StoredActivity}
  alias Thicket.Identity.Channel
  alias Thicket.Repo
  alias Thicket.Social.Follow

  def follow(%Channel{} = channel, %RemoteActor{cache_state: :warm} = remote_actor) do
    activity = follow_activity(channel, remote_actor)
    stored = stored(activity, channel, remote_actor, :outbound, :pending)
    activity_id = Ecto.Changeset.get_field(stored, :id)

    Multi.new()
    |> Multi.insert(:activity, stored)
    |> Multi.insert(
      :follow,
      %Follow{follower_channel_id: channel.id, followed_remote_actor_id: remote_actor.id}
      |> Follow.changeset(%{state: :pending, activity_iri: activity.id.value})
    )
    |> Deliveries.add_to_multi(activity_id, remote_actor)
    |> Repo.transaction()
  end

  def follow(%Channel{}, %RemoteActor{}), do: {:error, :remote_actor_unavailable}

  def follow_account(%Channel{} = channel, account, opts \\ []) when is_binary(account) do
    with {:ok, username, domain} <- parse_account(account),
         false <- Thicket.Moderation.domain_suspended?(domain),
         {:ok, remote_actor} <-
           Thicket.Federation.RemoteActors.discover_account(
             username,
             domain,
             Keyword.put(opts, :channel, channel)
           ) do
      follow(channel, remote_actor)
    else
      true -> {:error, :domain_suspended}
      error -> error
    end
  end

  def list_remote_following(%Channel{id: channel_id}) do
    Follow
    |> where([follow], follow.follower_channel_id == ^channel_id)
    |> join(:inner, [follow], actor in RemoteActor,
      on: actor.id == follow.followed_remote_actor_id
    )
    |> order_by([follow], desc: follow.inserted_at)
    |> select([follow, actor], {follow, actor})
    |> Repo.all()
  end

  def undo_follow(%Channel{id: channel_id} = channel, %RemoteActor{id: remote_id} = remote_actor) do
    case Repo.get_by(Follow, follower_channel_id: channel_id, followed_remote_actor_id: remote_id) do
      nil -> {:error, :not_following}
      follow -> create_undo(channel, remote_actor, follow)
    end
  end

  def handle(%Activity{type: "Follow"} = activity, %RemoteActor{} = actor, %Channel{} = target),
    do: inbound_follow(activity, actor, target)

  def handle(%Activity{type: type} = activity, %RemoteActor{} = actor, %Channel{} = target)
      when type in ["Accept", "Reject"],
      do: inbound_response(activity, actor, target)

  def handle(%Activity{type: "Undo"} = activity, %RemoteActor{} = actor, %Channel{} = target),
    do: inbound_undo(activity, actor, target)

  def handle(%Activity{}, %RemoteActor{}, %Channel{}), do: {:error, :unsupported_follow_activity}

  defp inbound_follow(activity, actor, target) do
    with :ok <- actor_matches(activity, actor),
         %IRI{value: object_iri} <- activity.object,
         true <- object_iri == Thicket.Federation.actor_iri(target).value do
      response = response_activity("Accept", target, actor, activity)
      stored_response = stored(response, target, actor, :outbound, :pending)
      response_id = Ecto.Changeset.get_field(stored_response, :id)

      Multi.new()
      |> Multi.insert(
        :follow,
        %Follow{follower_remote_actor_id: actor.id, followed_channel_id: target.id}
        |> Follow.changeset(%{
          state: :accepted,
          activity_iri: activity.id.value,
          response_activity_iri: response.id.value
        })
      )
      |> Multi.insert(:response, stored_response)
      |> Deliveries.add_to_multi(response_id, actor)
      |> Repo.transaction()
    else
      false -> {:error, :wrong_follow_target}
      nil -> {:error, :invalid_follow_object}
      error -> error
    end
  end

  defp inbound_response(activity, actor, target) do
    with :ok <- actor_matches(activity, actor),
         {:ok, object_iri} <- referenced_activity_iri(activity.object),
         %Follow{} = follow <-
           Repo.get_by(Follow,
             follower_channel_id: target.id,
             followed_remote_actor_id: actor.id,
             activity_iri: object_iri
           ) do
      state = if activity.type == "Accept", do: :accepted, else: :rejected

      follow
      |> Follow.changeset(%{state: state, response_activity_iri: activity.id.value})
      |> Repo.update()
    else
      nil -> {:error, :unknown_follow}
      error -> error
    end
  end

  defp inbound_undo(activity, actor, target) do
    with :ok <- actor_matches(activity, actor),
         {:ok, object_iri} <- referenced_activity_iri(activity.object),
         %Follow{} = follow <-
           Repo.get_by(Follow,
             follower_remote_actor_id: actor.id,
             followed_channel_id: target.id,
             activity_iri: object_iri
           ),
         {:ok, _} <- Repo.delete(follow) do
      {:ok, :undone}
    else
      nil -> {:error, :unknown_follow}
      error -> error
    end
  end

  defp create_undo(channel, remote_actor, follow) do
    actor_iri = Thicket.Federation.actor_iri(channel)
    activity_iri = activity_iri()

    undo = %Activity{
      id: activity_iri,
      type: "Undo",
      actor: actor_iri,
      object: IRI.parse!(follow.activity_iri),
      published: now_iso8601(),
      recipients: %Thicket.Federation.Recipients{to: [IRI.parse!(remote_actor.canonical_iri)]}
    }

    stored_undo = stored(undo, channel, remote_actor, :outbound, :pending)
    undo_id = Ecto.Changeset.get_field(stored_undo, :id)

    Multi.new()
    |> Multi.insert(:activity, stored_undo)
    |> Multi.delete(:follow, follow)
    |> Deliveries.add_to_multi(undo_id, remote_actor)
    |> Repo.transaction()
  end

  defp follow_activity(channel, remote_actor) do
    %Activity{
      id: activity_iri(),
      type: "Follow",
      actor: Thicket.Federation.actor_iri(channel),
      object: IRI.parse!(remote_actor.canonical_iri),
      published: now_iso8601(),
      recipients: %Thicket.Federation.Recipients{to: [IRI.parse!(remote_actor.canonical_iri)]}
    }
  end

  defp response_activity(type, channel, remote_actor, followed_activity) do
    %Activity{
      id: activity_iri(),
      type: type,
      actor: Thicket.Federation.actor_iri(channel),
      object: followed_activity,
      published: now_iso8601(),
      recipients: %Thicket.Federation.Recipients{to: [IRI.parse!(remote_actor.canonical_iri)]}
    }
  end

  defp stored(activity, channel, remote_actor, direction, state) do
    %StoredActivity{id: Ecto.UUID.generate()}
    |> StoredActivity.changeset(%{
      activity_iri: activity.id.value,
      activity_type: activity.type,
      actor_iri: activity.actor.value,
      object_iri: object_iri(activity.object),
      payload: Serializer.to_map(activity),
      direction: direction,
      state: state,
      local_channel_id: channel.id,
      remote_actor_id: remote_actor.id
    })
  end

  defp actor_matches(%Activity{actor: %IRI{value: iri}}, %RemoteActor{canonical_iri: iri}),
    do: :ok

  defp actor_matches(_, _), do: {:error, :actor_mismatch}

  defp referenced_activity_iri(%IRI{value: value}), do: {:ok, value}
  defp referenced_activity_iri(%Activity{id: %IRI{value: value}}), do: {:ok, value}
  defp referenced_activity_iri(_), do: {:error, :invalid_activity_reference}

  defp object_iri(%IRI{value: value}), do: value
  defp object_iri(%Activity{id: %IRI{value: value}}), do: value
  defp object_iri(_), do: nil

  defp activity_iri,
    do: IRI.parse!("#{Thicket.Federation.origin()}/ap/activities/#{Ecto.UUID.generate()}")

  defp now_iso8601, do: DateTime.utc_now(:second) |> DateTime.to_iso8601()

  defp parse_account(account) do
    account = String.trim_leading(String.trim(account), "@")

    case String.split(account, "@", parts: 2) do
      [username, domain]
      when username != "" and domain != "" ->
        if Regex.match?(~r/^[a-zA-Z0-9._-]+$/, username) and
             Regex.match?(~r/^[a-zA-Z0-9.-]+$/, domain) do
          {:ok, username, String.downcase(domain)}
        else
          {:error, :invalid_account}
        end

      _ ->
        {:error, :invalid_account}
    end
  end
end
