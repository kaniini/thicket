defmodule ThicketWeb.ChannelLive.Show do
  use ThicketWeb, :live_view
  alias Thicket.{Identity, Social}

  @impl true
  def mount(%{"handle" => handle}, _session, socket) do
    case Identity.get_channel_by_handle(handle) do
      nil -> {:ok, socket |> put_flash(:error, "Channel not found") |> push_navigate(to: ~p"/discover")}
      channel ->
        posts = Social.list_channel_posts(channel)
        {:ok, socket |> assign(:channel, channel) |> assign(:posts_empty?, posts == []) |> stream(:posts, posts)}
    end
  end

  @impl true
  def handle_event("block", _params, socket) do
    case Thicket.Moderation.block(socket.assigns.current_scope.channel, socket.assigns.channel) do
      {:ok, _} -> {:noreply, put_flash(socket, :info, "Channel blocked")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Could not block: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <header class="mb-8 rounded-3xl bg-emerald-950 p-8 text-white">
        <h1 class="text-4xl font-black">{@channel.display_name}</h1><p class="text-emerald-200">@{@channel.handle}</p>
        <p class="mt-4 max-w-prose whitespace-pre-wrap">{@channel.biography}</p>
        <button :if={@current_scope && @current_scope.channel.id != @channel.id} phx-click="block" class="mt-5 rounded-full border border-emerald-300 px-4 py-2 text-sm">Block channel</button>
      </header>
      <p :if={@posts_empty?} class="text-slate-500">This channel has not published yet.</p>
      <div id="channel-posts" phx-update="stream" class="space-y-6">
        <.post_card :for={{id, post} <- @streams.posts} id={id} post={post} current_scope={@current_scope} />
      </div>
    </Layouts.app>
    """
  end
end
