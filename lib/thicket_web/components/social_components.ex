defmodule ThicketWeb.SocialComponents do
  use Phoenix.Component
  use ThicketWeb, :verified_routes

  attr :post, :map, required: true
  attr :current_scope, :map, default: nil
  attr :id, :string, default: nil

  def post_card(assigns) do
    ~H"""
    <article
      id={@id || "post-#{@post.id}"}
      class="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm transition hover:shadow-md"
    >
      <header class="mb-4 flex items-center justify-between gap-3">
        <.link
          navigate={~p"/channels/#{@post.channel.handle}"}
          class="font-semibold text-emerald-800 hover:underline"
        >
          {@post.channel.display_name}
          <span class="font-normal text-slate-500">@{@post.channel.handle}</span>
        </.link>
        <time class="text-xs text-slate-500">
          {Calendar.strftime(@post.published_at, "%b %-d, %Y · %H:%M")}
        </time>
      </header>
      <%= if @post.title do %>
        <h2 class="mb-3 text-2xl font-bold text-slate-900">{@post.title}</h2>
      <% end %>
      <%= if @post.content_warning do %>
        <details class="mb-3 rounded-xl bg-amber-50 p-3">
          <summary class="cursor-pointer font-medium">{@post.content_warning}</summary>
          <.rendered_post html={@post.rendered_html} post_id={@post.id} />
        </details>
      <% else %>
        <.rendered_post html={@post.rendered_html} post_id={@post.id} />
      <% end %>
      <div :if={@post.attachments != []} class="mt-4 grid gap-3 sm:grid-cols-2">
        <img
          :for={attachment <- @post.attachments}
          src={Thicket.Storage.url(attachment.storage_key)}
          alt={attachment.description}
          class="h-auto w-full rounded-2xl"
          loading="lazy"
        />
      </div>
      <div :if={hashtags(@post.source) != []} class="mt-4 flex flex-wrap gap-2">
        <.link
          :for={tag <- hashtags(@post.source)}
          navigate={~p"/tags/#{tag}"}
          class="rounded-full bg-emerald-50 px-3 py-1 text-xs font-semibold text-emerald-800"
        >
          #{tag}
        </.link>
      </div>
      <footer class="mt-4 flex gap-4 text-sm text-slate-600">
        <.link navigate={~p"/posts/#{@post.id}"} class="hover:text-emerald-700">Comments</.link>
        <%= if @current_scope && @current_scope.channel do %>
          <button phx-click="like" phx-value-id={@post.id} class="hover:text-rose-600">Like</button>
          <button phx-click="unlike" phx-value-id={@post.id} class="hover:text-slate-900">
            Unlike
          </button>
          <button phx-click="share" phx-value-id={@post.id} class="hover:text-emerald-700">
            Share
          </button>
          <button phx-click="unshare" phx-value-id={@post.id} class="hover:text-slate-900">
            Unshare
          </button>
        <% end %>
      </footer>
    </article>
    """
  end

  attr :html, :string, required: true
  attr :post_id, :string, required: true

  def rendered_post(assigns) do
    document =
      "<!doctype html><meta charset=utf-8><meta http-equiv=Content-Security-Policy content=\"default-src 'none'; img-src https: data:; style-src 'unsafe-inline';\"><style>html{color:#172033;font:16px system-ui;overflow-wrap:anywhere}body{margin:0}img{max-width:100%;height:auto}a{color:#047857}</style>" <>
        assigns.html

    assigns = assign(assigns, :document, document)

    ~H"""
    <iframe
      id={"rendered-post-#{@post_id}"}
      title="Post content"
      sandbox="allow-popups"
      srcdoc={@document}
      class="min-h-40 w-full border-0"
      loading="lazy"
    >
    </iframe>
    """
  end

  defp hashtags(source) do
    Regex.scan(~r/(?:^|[^\p{L}\p{N}_])#([\p{L}\p{N}_-]{1,64})/u, source, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq_by(&String.downcase/1)
  end
end
