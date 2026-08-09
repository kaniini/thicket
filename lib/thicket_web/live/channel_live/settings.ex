defmodule ThicketWeb.ChannelLive.Settings do
  use ThicketWeb, :live_view
  alias Thicket.Identity

  @impl true
  def mount(%{"handle" => handle}, _session, socket) do
    channel = Identity.get_channel_by_handle(handle)

    if channel do
      channel = Identity.get_channel_for_user!(socket.assigns.current_scope.user, channel.id)

      links =
        Identity.get_channel_by_handle(channel.handle).links
        |> Enum.map_join("\n", &"#{&1.label} #{&1.url}")

      {:ok,
       socket
       |> assign(:channel, channel)
       |> assign(:form, to_form(Identity.change_channel(channel, %{profile_links: links})))}
    else
      {:ok, socket |> put_flash(:error, "Channel not found") |> push_navigate(to: ~p"/channels")}
    end
  end

  @impl true
  def handle_event("save", %{"channel" => params}, socket) do
    case Identity.update_channel(
           socket.assigns.current_scope.user,
           socket.assigns.channel,
           params
         ) do
      {:ok, channel} ->
        {:noreply,
         socket
         |> assign(:channel, channel)
         |> assign(:form, to_form(Identity.change_channel(channel)))
         |> put_flash(:info, "Channel updated")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <h1 class="mb-8 text-4xl font-black">Edit @{@channel.handle}</h1>
      <.form for={@form} id="channel-settings-form" phx-submit="save" class="max-w-2xl space-y-5">
        <.input field={@form[:display_name]} label="Display name" required /><.input
          field={@form[:biography]}
          type="textarea"
          label="Biography"
        /><.input field={@form[:avatar_url]} type="url" label="Avatar URL" /><.input
          field={@form[:header_url]}
          type="url"
          label="Header URL"
        /><.input
          field={@form[:profile_links]}
          type="textarea"
          label="Profile links (one label and HTTPS URL per line)"
        /><.input
          field={@form[:comments_default_locked]}
          type="checkbox"
          label="Lock comments on new posts by default"
        /><.button class="btn btn-primary">Save changes</.button>
      </.form>
    </Layouts.app>
    """
  end
end
