defmodule ThicketWeb.Admin.FederationLiveTest do
  use ThicketWeb.ConnCase

  import Phoenix.LiveViewTest
  import Thicket.IdentityFixtures

  test "administrators can inspect sanitized federation diagnostics", %{conn: conn} do
    user = user_fixture() |> Ecto.Changeset.change(admin: true) |> Thicket.Repo.update!()

    {:ok, _} =
      Thicket.Federation.Audit.record(%{
        direction: :outbound,
        category: "fetch",
        result: :failed,
        domain: "remote.example",
        details: %{code: :timeout}
      })

    conn = log_in_user(conn, user)
    {:ok, view, html} = live(conn, ~p"/admin/federation")
    assert html =~ "Federation diagnostics"
    assert has_element?(view, "#federation-events", "remote.example")
    assert has_element?(view, "#federation-events", "timeout")
  end

  test "non-administrators are redirected", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())
    assert {:error, {:live_redirect, %{to: "/home"}}} = live(conn, ~p"/admin/federation")
  end
end
