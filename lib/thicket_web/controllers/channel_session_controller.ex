defmodule ThicketWeb.ChannelSessionController do
  use ThicketWeb, :controller
  alias Thicket.Identity

  def create(conn, %{"channel_id" => channel_id}) do
    channel = Identity.get_channel_for_user!(conn.assigns.current_scope.user, channel_id)

    conn
    |> put_session(:active_channel_id, channel.id)
    |> put_flash(:info, "Now acting as @#{channel.handle}")
    |> redirect(to: ~p"/home")
  end
end
