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
    assert response_content_type(conn, :json)
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
    assert outbox["totalItems"] == 1
    assert [object] = outbox["orderedItems"]
    assert object["type"] == "Article"
    assert object["source"]["mediaType"] == "text/markdown"

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
end
