defmodule ThicketWeb.ChannelLive.Index do
  use ThicketWeb, :live_view
  alias Thicket.Identity
  alias Thicket.Identity.Channel

  @impl true
  def mount(_params, _session, socket) do
    channels = Identity.list_channels(socket.assigns.current_scope.user)
    {:ok, socket |> assign(:form, to_form(Identity.change_channel(%Channel{}))) |> stream(:channels, channels)}
  end

  @impl true
  def handle_event("create", %{"channel" => params}, socket) do
    case Identity.create_channel(socket.assigns.current_scope.user, params) do
      {:ok, channel} -> {:noreply, socket |> stream_insert(:channels, channel) |> assign(:form, to_form(Identity.change_channel(%Channel{})))}
      {:error, %Ecto.Changeset{} = changeset} -> {:noreply, assign(socket, :form, to_form(changeset))}
      {:error, _operation, %Ecto.Changeset{} = changeset, _changes} -> {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <h1 class="mb-8 text-4xl font-black">Your channels</h1>
      <div id="channels" phx-update="stream" class="mb-10 grid gap-4 sm:grid-cols-2">
        <article :for={{id, channel} <- @streams.channels} id={id} class="rounded-2xl border bg-white p-5"><h2 class="text-xl font-bold">{channel.display_name}</h2><p class="text-slate-500">@{channel.handle}</p><.link navigate={~p"/channels/#{channel.handle}/settings"} class="mt-3 inline-block text-emerald-700">Edit channel</.link></article>
      </div>
      <h2 class="mb-4 text-2xl font-bold">Create another channel</h2>
      <.form for={@form} id="channel-form" phx-submit="create" class="max-w-lg space-y-4"><.input field={@form[:handle]} label="Handle" required /><.input field={@form[:display_name]} label="Display name" required /><.button class="btn btn-primary">Create channel</.button></.form>
    </Layouts.app>
    """
  end
end
