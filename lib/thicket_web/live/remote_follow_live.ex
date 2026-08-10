defmodule ThicketWeb.RemoteFollowLive do
  use ThicketWeb, :live_view

  alias Thicket.Federation.Follows

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:form, to_form(%{"account" => ""}, as: :remote_follow))
     |> assign_following()}
  end

  @impl true
  def handle_event("follow", %{"remote_follow" => %{"account" => account}}, socket) do
    case Follows.follow_account(socket.assigns.current_scope.channel, account) do
      {:ok, _changes} ->
        {:noreply,
         socket
         |> put_flash(:info, "Follow request sent")
         |> assign(:form, to_form(%{"account" => ""}, as: :remote_follow))
         |> assign_following()}

      {:error, _operation, changeset, _changes} ->
        {:noreply, put_flash(socket, :error, follow_error(changeset))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, follow_error(reason))}
    end
  end

  def handle_event("unfollow", %{"actor-id" => actor_id}, socket) do
    channel = socket.assigns.current_scope.channel

    case Enum.find(Follows.list_remote_following(channel), fn {_follow, actor} ->
           actor.id == actor_id
         end) do
      {_follow, actor} ->
        case Follows.undo_follow(channel, actor) do
          {:ok, _} ->
            {:noreply, socket |> put_flash(:info, "Unfollow sent") |> assign_following()}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, follow_error(reason))}
        end

      nil ->
        {:noreply, put_flash(socket, :error, "That remote follow is no longer available")}
    end
  end

  defp assign_following(socket) do
    assign(
      socket,
      :following,
      Follows.list_remote_following(socket.assigns.current_scope.channel)
    )
  end

  defp follow_error(%Ecto.Changeset{}), do: "That channel is already being followed"
  defp follow_error(:invalid_account), do: "Enter an address such as alice@example.social"
  defp follow_error(:domain_suspended), do: "That domain is suspended on this server"
  defp follow_error(reason), do: "Could not follow that channel: #{inspect(reason)}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="grid gap-8 lg:grid-cols-[minmax(0,1fr)_22rem]">
        <section>
          <p class="text-sm font-bold uppercase tracking-[0.18em] text-emerald-700">Social graph</p>
          <h1 class="mt-2 text-4xl font-black text-slate-950">Remote following</h1>
          <p class="mt-3 max-w-2xl text-slate-600">
            Follow a channel on another ActivityPub server as <span class="font-semibold">{@current_scope.channel.display_name}</span>.
          </p>

          <div id="remote-following" class="mt-8 space-y-3">
            <p
              :if={@following == []}
              id="remote-following-empty"
              class="rounded-2xl border bg-white p-6 text-slate-500"
            >
              No remote follow requests yet.
            </p>
            <article
              :for={{follow, actor} <- @following}
              id={"remote-follow-#{follow.id}"}
              class="flex items-center justify-between gap-4 rounded-2xl border bg-white p-5"
            >
              <div class="min-w-0">
                <p class="truncate font-bold text-slate-900">
                  {actor.name || actor.preferred_username || actor.canonical_iri}
                </p>
                <p class="truncate text-sm text-slate-500">{actor.canonical_iri}</p>
                <span class="mt-2 inline-flex rounded-full bg-slate-100 px-2 py-1 text-xs font-bold uppercase text-slate-600">
                  {follow.state}
                </span>
              </div>
              <button
                id={"unfollow-remote-#{actor.id}"}
                phx-click="unfollow"
                phx-value-actor-id={actor.id}
                class="rounded-xl border px-3 py-2 text-sm font-bold text-rose-700 transition hover:border-rose-300 hover:bg-rose-50"
              >
                Unfollow
              </button>
            </article>
          </div>
        </section>

        <aside class="h-fit rounded-3xl border bg-white p-6 shadow-sm">
          <h2 class="text-xl font-black text-slate-900">Find a remote channel</h2>
          <.form for={@form} id="remote-follow-form" phx-submit="follow" class="mt-5 space-y-4">
            <.input
              field={@form[:account]}
              label="Fediverse address"
              placeholder="alice@example.social"
              autocomplete="off"
              required
            />
            <.button class="w-full">Send follow request</.button>
          </.form>
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
