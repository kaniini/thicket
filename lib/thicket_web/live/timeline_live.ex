defmodule ThicketWeb.TimelineLive do
  use ThicketWeb, :live_view
  alias Thicket.Social

  @impl true
  def mount(params, _session, socket) do
    posts =
      case socket.assigns.live_action do
        :home -> Social.list_home_posts(socket.assigns.current_scope.channel)
        :discovery -> Social.list_discovery_posts()
        :tag -> Social.list_tag_posts(params["tag"])
      end

    title =
      case socket.assigns.live_action do
        :home -> "Home"
        :discovery -> "Discover"
        :tag -> "##{params["tag"]}"
      end

    {:ok,
     socket
     |> assign(:page_title, title)
     |> assign(:posts_empty?, posts == [])
     |> stream(:posts, posts)}
  end

  @impl true
  def handle_event(action, %{"id" => id}, socket)
      when action in ["like", "unlike", "share", "unshare"] do
    post = Social.get_post!(id)
    channel = socket.assigns.current_scope.channel

    result =
      case action do
        "like" -> Social.like(channel, post)
        "unlike" -> Social.unlike(channel, post)
        "share" -> Social.share(channel, post)
        "unshare" -> Social.unshare(channel, post)
      end

    case result do
      {:ok, _} -> {:noreply, put_flash(socket, :info, "Saved")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not save that interaction")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="space-y-6">
        <header class="flex items-end justify-between">
          <div>
            <p class="text-sm font-semibold uppercase tracking-widest text-emerald-700">Thicket</p>
            <h1 class="text-4xl font-black text-slate-900">{@page_title}</h1>
          </div>
          <.link
            :if={@current_scope}
            navigate={~p"/compose"}
            class="rounded-full bg-emerald-700 px-5 py-3 font-semibold text-white hover:bg-emerald-800"
          >
            New post
          </.link>
        </header>
        <p
          :if={@posts_empty?}
          class="rounded-2xl border border-dashed border-slate-300 p-10 text-center text-slate-500"
        >
          Nothing has grown here yet.
        </p>
        <div id="timeline-posts" phx-update="stream" class="space-y-6">
          <.post_card
            :for={{id, post} <- @streams.posts}
            id={id}
            post={post}
            current_scope={@current_scope}
          />
        </div>
      </section>
    </Layouts.app>
    """
  end
end
