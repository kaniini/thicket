defmodule ThicketWeb.FederationControllerTest do
  use ThicketWeb.ConnCase

  import Thicket.IdentityFixtures

  alias Thicket.Social

  setup do
    {:ok, user} = Thicket.Identity.register_invited_user(valid_registration_attributes())
    channel = user |> Thicket.Identity.list_channels() |> hd()
    %{channel: channel}
  end

  test "discovers a channel with WebFinger", %{conn: conn, channel: channel} do
    authority = Thicket.Federation.authority()
    conn = get(conn, "/.well-known/webfinger", resource: "acct:#{channel.handle}@#{authority}")
    assert get_resp_header(conn, "content-type") == ["application/jrd+json; charset=utf-8"]
    assert body = json_response(conn, 200)
    assert body["subject"] == "acct:#{channel.handle}@#{authority}"
    assert [%{"href" => actor, "rel" => "self"}] = body["links"]
    assert actor == "#{Thicket.Federation.origin()}/ap/channels/#{channel.handle}"
  end

  test "serves a typed actor with its public signing key", %{conn: conn, channel: channel} do
    conn = get(conn, "/ap/channels/#{channel.handle}")
    assert get_resp_header(conn, "content-type") == ["application/activity+json; charset=utf-8"]
    assert actor = json_response(conn, 200)
    assert actor["type"] == "Person"
    assert actor["preferredUsername"] == channel.handle
    assert actor["publicKey"]["owner"] == actor["id"]
  end

  test "serves collections and dereferenceable public posts", %{conn: conn, channel: channel} do
    assert {:ok, post} =
             Social.create_post(channel, %{
               title: "Federated post",
               source: "hello *world*",
               source_format: :markdown,
               state: :published
             })

    outbox = conn |> get("/ap/channels/#{channel.handle}/outbox") |> json_response(200)
    assert outbox["type"] == "OrderedCollection"
    assert outbox["totalItems"] == 0
    refute Map.has_key?(outbox, "orderedItems")

    object = conn |> recycle() |> get("/ap/posts/#{post.id}") |> json_response(200)
    assert object["id"] == "#{Thicket.Federation.origin()}/ap/posts/#{post.id}"
    assert object["content"] =~ "<em>world</em>"

    for collection <- ~w(followers following) do
      body =
        conn
        |> recycle()
        |> get("/ap/channels/#{channel.handle}/#{collection}")
        |> json_response(200)

      assert body["totalItems"] == 0
    end
  end

  test "does not expose drafts or unknown local accounts", %{conn: conn, channel: channel} do
    assert {:ok, draft} =
             Social.create_post(channel, %{
               source: "secret",
               source_format: :markdown,
               state: :draft
             })

    assert conn |> get("/ap/posts/#{draft.id}") |> response(404)
    assert conn |> recycle() |> get("/ap/channels/missing") |> response(404)
  end

  test "keeps the shared inbox reserved until content federation", %{conn: conn} do
    assert conn
           |> put_req_header("content-type", "application/activity+json")
           |> post("/ap/inbox", "{}")
           |> response(501)
  end

  test "authenticates and idempotently accepts an inbound Follow", %{conn: conn, channel: channel} do
    {:ok, local_key} = Thicket.Federation.KeyStore.ensure_key(channel)
    remote_iri = "https://remote.example/users/alice"
    key_id = "#{remote_iri}#main-key"
    now = DateTime.utc_now(:second)

    remote =
      Thicket.Repo.insert!(%Thicket.Federation.RemoteActor{
        canonical_iri: remote_iri,
        actor_type: "Person",
        preferred_username: "alice",
        inbox_iri: "#{remote_iri}/inbox",
        public_key_id: key_id,
        public_key_pem: local_key.public_key_pem,
        source_authority: "remote.example",
        cache_state: :warm,
        fetched_at: now,
        validated_at: now,
        last_accessed_at: now
      })

    activity = %Thicket.Federation.Activity{
      id: Thicket.Federation.IRI.parse!("https://remote.example/activities/follow-1"),
      type: "Follow",
      actor: Thicket.Federation.IRI.parse!(remote.canonical_iri),
      object: Thicket.Federation.actor_iri(channel)
    }

    body = Thicket.Federation.Serializer.encode!(activity)
    path = "/ap/channels/#{channel.handle}/inbox"
    target = Thicket.Federation.IRI.parse!("http://#{conn.host}#{path}")

    assert {:ok, signed_headers} =
             Thicket.Federation.HTTPSignature.sign(:post, target, body, key_id, local_key)

    conn =
      Enum.reduce(signed_headers, conn, fn
        {"host", _value}, conn -> conn
        {name, value}, conn -> put_req_header(conn, name, value)
      end)
      |> put_req_header("content-type", "application/activity+json")

    verification_headers = [{"host", conn.host} | conn.req_headers]

    assert {:ok, ^key_id} =
             Thicket.Federation.HTTPSignature.verify(
               :post,
               path,
               verification_headers,
               body,
               local_key.public_key_pem
             )

    assert conn |> post(path, body) |> response(202)

    replay_conn =
      Enum.reduce(signed_headers, recycle(conn), fn
        {"host", _value}, conn -> conn
        {name, value}, conn -> put_req_header(conn, name, value)
      end)
      |> put_req_header("content-type", "application/activity+json")

    assert replay_conn |> post(path, body) |> response(202)

    assert Thicket.Repo.get_by(Thicket.Social.Follow,
             follower_remote_actor_id: remote.id,
             followed_channel_id: channel.id
           )

    followers =
      conn
      |> recycle()
      |> get("/ap/channels/#{channel.handle}/followers")
      |> json_response(200)

    assert remote.canonical_iri in followers["orderedItems"]
  end
end
