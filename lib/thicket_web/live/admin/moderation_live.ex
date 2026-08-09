defmodule ThicketWeb.Admin.ModerationLive do
  use ThicketWeb, :live_view
  alias Thicket.Moderation

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    if user.admin do
      reports = Moderation.list_open_reports(user)

      {:ok,
       socket
       |> assign(:empty?, reports == [])
       |> assign(:domain_form, to_form(%{"action" => "suspend"}, as: :domain_rule))
       |> stream(:reports, reports)}
    else
      {:ok,
       socket
       |> put_flash(:error, "Administrator access required")
       |> push_navigate(to: ~p"/home")}
    end
  end

  @impl true
  def handle_event("resolve", %{"id" => id, "state" => state}, socket) do
    report = Moderation.get_report!(socket.assigns.current_scope.user, id)
    resolution = if state == "resolved", do: :resolved, else: :dismissed

    {:ok, %{report: report}} =
      Moderation.resolve_report(socket.assigns.current_scope.user, report, resolution)

    {:noreply, stream_delete(socket, :reports, report)}
  end

  def handle_event("domain-rule", %{"domain_rule" => params}, socket) do
    case Moderation.put_domain_rule(socket.assigns.current_scope.user, params) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, "Domain suspended locally")}

      {:error, _operation, changeset, _changes} ->
        {:noreply, put_flash(socket, :error, "Could not add rule: #{inspect(changeset.errors)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <h1 class="mb-8 text-4xl font-black">Moderation</h1>
      <h2 class="mb-4 text-2xl font-bold">Open reports</h2>
      <p :if={@empty?} class="text-slate-500">No open reports.</p>
      <div id="reports" phx-update="stream" class="space-y-3">
        <article
          :for={{id, report} <- @streams.reports}
          id={id}
          class="rounded-2xl border bg-white p-5"
        >
          <p class="font-semibold">{report.subject_type} · {report.subject_id}</p>
          <p class="my-3 whitespace-pre-wrap">{report.reason}</p>
          <div class="flex gap-3">
            <button
              phx-click="resolve"
              phx-value-id={report.id}
              phx-value-state="resolved"
              class="text-emerald-700"
            >
              Resolve
            </button>
            <button
              phx-click="resolve"
              phx-value-id={report.id}
              phx-value-state="dismissed"
              class="text-slate-500"
            >
              Dismiss
            </button>
          </div>
        </article>
      </div>
      <h2 class="mb-4 mt-10 text-2xl font-bold">Suspend a domain</h2>
      <.form
        for={@domain_form}
        id="domain-rule-form"
        phx-submit="domain-rule"
        class="max-w-xl space-y-3"
      >
        <.input field={@domain_form[:domain]} label="Domain" required /><.input
          field={@domain_form[:reason]}
          label="Internal reason"
        /><input type="hidden" name="domain_rule[action]" value="suspend" />
        <.button class="btn btn-primary">
          Suspend locally
        </.button>
      </.form>
    </Layouts.app>
    """
  end
end
