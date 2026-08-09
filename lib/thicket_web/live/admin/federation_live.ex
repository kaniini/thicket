defmodule ThicketWeb.Admin.FederationLive do
  use ThicketWeb, :live_view

  alias Thicket.Federation.Audit

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    if user.admin do
      events = Audit.list_recent(user)

      {:ok,
       socket
       |> assign(:empty?, events == [])
       |> stream(:events, events)}
    else
      {:ok,
       socket
       |> put_flash(:error, "Administrator access required")
       |> push_navigate(to: ~p"/home")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p class="text-sm font-bold uppercase tracking-[0.18em] text-emerald-700">Operations</p>
          <h1 class="mt-2 text-4xl font-black text-slate-950">Federation diagnostics</h1>
        </div>
        <p class="max-w-lg text-sm text-slate-600">
          Recent boundary decisions. Request bodies, credentials, and private keys are never retained here.
        </p>
      </div>

      <p
        :if={@empty?}
        id="federation-events-empty"
        class="rounded-2xl border bg-white p-6 text-slate-500"
      >
        No federation events have been recorded.
      </p>

      <div
        id="federation-events"
        phx-update="stream"
        class="overflow-hidden rounded-2xl border bg-white"
      >
        <article
          :for={{id, event} <- @streams.events}
          id={id}
          class="grid gap-2 border-b p-5 last:border-b-0 md:grid-cols-[9rem_9rem_1fr_auto] md:items-center"
        >
          <div>
            <span class={[
              "inline-flex rounded-full px-2.5 py-1 text-xs font-bold uppercase tracking-wide",
              event.result == :accepted && "bg-emerald-100 text-emerald-800",
              event.result == :rejected && "bg-amber-100 text-amber-800",
              event.result == :failed && "bg-rose-100 text-rose-800"
            ]}>
              {event.result}
            </span>
          </div>
          <p class="font-semibold text-slate-800">{event.direction} · {event.category}</p>
          <div class="min-w-0">
            <p class="truncate text-sm font-medium text-slate-700">
              {event.domain || "local boundary"}
            </p>
            <p :if={event.iri} class="truncate text-xs text-slate-500">{event.iri}</p>
            <p class="mt-1 font-mono text-xs text-slate-500">{inspect(event.details)}</p>
          </div>
          <time class="text-xs text-slate-500">
            {Calendar.strftime(event.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}
          </time>
        </article>
      </div>
    </Layouts.app>
    """
  end
end
