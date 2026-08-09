defmodule ThicketWeb.Admin.InvitationLive do
  use ThicketWeb, :live_view
  alias Thicket.Identity

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_scope.user.admin do
      {:ok,
       socket
       |> assign(:form, to_form(%{"max_uses" => 1}, as: :invitation))
       |> assign(:new_code, nil)
       |> stream(:invitations, Identity.list_invitations())}
    else
      {:ok,
       socket
       |> put_flash(:error, "Administrator access required")
       |> push_navigate(to: ~p"/home")}
    end
  end

  @impl true
  def handle_event("create", %{"invitation" => params}, socket) do
    case Identity.create_invitation(socket.assigns.current_scope.user, params) do
      {:ok, invitation, secret} ->
        {:noreply,
         socket
         |> assign(:new_code, secret)
         |> stream_insert(:invitations, Thicket.Repo.preload(invitation, :issuer), at: 0)}

      {:error, changeset} ->
        {:noreply,
         put_flash(socket, :error, "Could not create invitation: #{inspect(changeset.errors)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <h1 class="mb-8 text-4xl font-black">Invitations</h1>
      <div :if={@new_code} class="mb-6 rounded-2xl bg-emerald-50 p-5">
        <p class="font-semibold">Copy this code now; it will not be shown again.</p>
        <code class="break-all">{@new_code}</code>
      </div>
      <.form for={@form} id="invitation-form" phx-submit="create" class="mb-10 flex items-end gap-3">
        <.input field={@form[:max_uses]} type="number" min="1" label="Maximum uses" /><.input
          field={@form[:expires_at]}
          type="datetime-local"
          label="Expires (optional)"
        /><.button class="btn btn-primary">Create code</.button>
      </.form>
      <div id="invitations" phx-update="stream" class="space-y-3">
        <article
          :for={{id, invite} <- @streams.invitations}
          id={id}
          class="rounded-xl border bg-white p-4"
        >
          {invite.redemption_count}/{invite.max_uses} uses · {if invite.revoked_at,
            do: "revoked",
            else: "active"}
        </article>
      </div>
    </Layouts.app>
    """
  end
end
