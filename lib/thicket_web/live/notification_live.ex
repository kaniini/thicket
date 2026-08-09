defmodule ThicketWeb.NotificationLive do
  use ThicketWeb, :live_view
  alias Thicket.Social

  @impl true
  def mount(_params, _session, socket) do
    notifications = Social.list_notifications(socket.assigns.current_scope.channel)
    {:ok, socket |> assign(:empty?, notifications == []) |> stream(:notifications, notifications)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <h1 class="mb-8 text-4xl font-black">Notifications</h1>
      <p :if={@empty?} class="text-slate-500">You are all caught up.</p>
      <div id="notifications" phx-update="stream" class="space-y-3">
        <article
          :for={{id, notification} <- @streams.notifications}
          id={id}
          class="rounded-2xl border bg-white p-5"
        >
          <span class="font-semibold">@{notification.actor_channel.handle}</span> {notification.kind}d your {notification.subject_type}.
        </article>
      </div>
    </Layouts.app>
    """
  end
end
