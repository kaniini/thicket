defmodule Thicket.Federation.RemoteActorsTest do
  use Thicket.DataCase

  alias Thicket.Federation.RemoteActors

  test "discovers, normalizes, caches, and refreshes a remote actor" do
    request = request_fun("Alice")

    assert {:ok, actor} =
             RemoteActors.discover_account("alice", "remote.example",
               resolver: &public_resolver/1,
               request_fun: request
             )

    assert actor.canonical_iri == "https://remote.example/users/alice"
    assert actor.preferred_username == "alice"
    assert actor.name == "Alice"
    assert actor.inbox_iri == "https://remote.example/users/alice/inbox"
    assert actor.public_key_pem =~ "BEGIN PUBLIC KEY"
    assert actor.cache_state == :warm
    assert actor.normalized_document["type"] == "Person"

    assert {:ok, cached} =
             RemoteActors.get_or_fetch(actor.canonical_iri,
               resolver: fn _ -> flunk("fresh actor should not be fetched") end
             )

    assert cached.id == actor.id
  end

  test "evicts warm payloads after 90 days and refetches cold identities" do
    assert {:ok, actor} =
             RemoteActors.get_or_fetch("https://remote.example/users/alice",
               resolver: &public_resolver/1,
               request_fun: request_fun("Before eviction")
             )

    old = DateTime.add(DateTime.utc_now(:second), -91 * 86_400)
    actor |> Ecto.Changeset.change(last_accessed_at: old) |> Repo.update!()

    assert {1, _} = RemoteActors.evict_stale()
    cold = Repo.reload!(actor)
    assert cold.cache_state == :cold
    assert is_nil(cold.normalized_document)
    assert is_nil(cold.public_key_pem)
    assert cold.canonical_iri == actor.canonical_iri

    assert {:ok, warm} =
             RemoteActors.get_or_fetch(cold.canonical_iri,
               resolver: &public_resolver/1,
               request_fun: request_fun("After eviction")
             )

    assert warm.cache_state == :warm
    assert warm.name == "After eviction"
  end

  test "rejects actors whose canonical identity changes authority" do
    request = fn _url, _headers, _opts ->
      evil_id = "https://evil.example/users/mallory"

      actor =
        actor_document("Mallory")
        |> Map.put("id", evil_id)
        |> Map.put("publicKey", %{
          "id" => "#{evil_id}#main-key",
          "owner" => evil_id,
          "publicKeyPem" => "-----BEGIN PUBLIC KEY-----\nkey\n-----END PUBLIC KEY-----"
        })

      activity_response(actor)
    end

    assert {:error, :actor_authority_mismatch} =
             RemoteActors.get_or_fetch("https://remote.example/users/alice",
               resolver: &public_resolver/1,
               request_fun: request
             )
  end

  defp request_fun(name) do
    fn url, _headers, _opts ->
      if String.contains?(url, "/.well-known/webfinger") do
        activity_response(
          %{
            "subject" => "acct:alice@remote.example",
            "links" => [
              %{
                "rel" => "self",
                "type" => "application/activity+json",
                "href" => "https://remote.example/users/alice"
              }
            ]
          },
          "application/jrd+json"
        )
      else
        activity_response(actor_document(name))
      end
    end
  end

  defp actor_document(name) do
    %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "id" => "https://remote.example/users/alice",
      "type" => "Person",
      "preferredUsername" => "alice",
      "name" => name,
      "inbox" => "https://remote.example/users/alice/inbox",
      "publicKey" => %{
        "id" => "https://remote.example/users/alice#main-key",
        "owner" => "https://remote.example/users/alice",
        "publicKeyPem" => "-----BEGIN PUBLIC KEY-----\nkey\n-----END PUBLIC KEY-----"
      }
    }
  end

  defp activity_response(document, type \\ "application/activity+json") do
    {:ok,
     %{
       status: 200,
       headers: %{"content-type" => [type], "etag" => ["W/\"actor-1\""]},
       body: Jason.encode!(document)
     }}
  end

  defp public_resolver(_host), do: {:ok, [{93, 184, 216, 34}]}
end
