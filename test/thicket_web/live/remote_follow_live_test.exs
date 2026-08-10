defmodule ThicketWeb.RemoteFollowLiveTest do
  use ThicketWeb.ConnCase

  import Phoenix.LiveViewTest
  import Thicket.IdentityFixtures

  alias Thicket.Federation.{Follows, RemoteActor}

  test "lists remote follow state for the current channel", %{conn: conn} do
    {:ok, user} = Thicket.Identity.register_invited_user(valid_registration_attributes())
    channel = user |> Thicket.Identity.list_channels() |> hd()
    remote = remote_actor_fixture()
    assert {:ok, _} = Follows.follow(channel, remote)

    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/following/remote")
    assert has_element?(view, "#remote-following", "Alice")
    assert has_element?(view, "#remote-following", "pending")
    assert has_element?(view, "#remote-follow-form")
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/following/remote")
  end

  defp remote_actor_fixture do
    now = DateTime.utc_now(:second)

    Thicket.Repo.insert!(%RemoteActor{
      canonical_iri: "https://remote.example/users/alice",
      actor_type: "Person",
      preferred_username: "alice",
      name: "Alice",
      inbox_iri: "https://remote.example/users/alice/inbox",
      public_key_id: "https://remote.example/users/alice#main-key",
      public_key_pem: "public key",
      source_authority: "remote.example",
      cache_state: :warm,
      fetched_at: now,
      validated_at: now,
      last_accessed_at: now
    })
  end
end
