defmodule ThicketWeb.MilestoneLiveTest do
  use ThicketWeb.ConnCase

  import Phoenix.LiveViewTest
  alias Thicket.{Identity, Repo, Social}

  setup %{conn: conn} do
    user = Thicket.IdentityFixtures.user_fixture()

    {:ok, channel} =
      Identity.create_channel(user, %{
        handle: "web#{System.unique_integer([:positive])}",
        display_name: "Web channel"
      })

    %{conn: log_in_user(conn, user), user: user, channel: channel}
  end

  test "compose, publish, and read a post", %{conn: conn, channel: channel} do
    {:ok, live, _html} = live(conn, ~p"/compose")

    assert render_submit(live, "save", %{
             "post" => %{
               "source" => "Hello **Thicket** #welcome",
               "source_format" => "markdown"
             },
             "intent" => "publish"
           })

    [post] = Social.list_channel_posts(channel)
    assert_redirect(live, ~p"/posts/#{post.id}")
    {:ok, _show, html} = live(build_conn(), ~p"/posts/#{post.id}")
    assert html =~ "rendered-post-#{post.id}"
  end

  test "home timeline and channel follow controls are usable", %{conn: conn, channel: channel} do
    {:ok, _post} =
      Social.create_post(channel, %{source: "home", source_format: :markdown, state: :published})

    assert {:ok, _live, html} = live(conn, ~p"/home")
    assert html =~ "Web channel"

    other_user = Thicket.IdentityFixtures.user_fixture()

    {:ok, other} =
      Identity.create_channel(other_user, %{handle: "followme", display_name: "Follow me"})

    {:ok, profile, html} = live(conn, ~p"/channels/#{other.handle}")
    assert html =~ "Follow"
    profile |> element("button", "Follow") |> render_click()
    assert Social.following?(channel, other)
  end

  test "administrators can open invite and moderation consoles", %{conn: conn, user: user} do
    user |> Ecto.Changeset.change(admin: true) |> Repo.update!()
    assert {:ok, _live, html} = live(conn, ~p"/admin/invitations")
    assert html =~ "Invitations"
    assert {:ok, _live, html} = live(conn, ~p"/admin/moderation")
    assert html =~ "Moderation"
  end
end
