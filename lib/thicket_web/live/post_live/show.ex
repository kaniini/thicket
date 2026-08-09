defmodule ThicketWeb.PostLive.Show do
  use ThicketWeb, :live_view
  alias Thicket.Social
  alias Thicket.Social.Comment

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    post = Social.get_post!(id)

    if post.state == :published && is_nil(post.deleted_at) do
      comments = Social.list_comments(post)
      {:ok, socket |> assign(:post, post) |> assign(:comment_form, to_form(Comment.changeset(%Comment{}, %{}))) |> assign(:report_form, to_form(%{"reason" => ""}, as: :report)) |> stream(:comments, comments)}
    else
      {:ok, socket |> put_flash(:error, "Post not found") |> push_navigate(to: ~p"/discover")}
    end
  end

  @impl true
  def handle_event("comment", %{"comment" => params}, socket) do
    case Social.create_comment(socket.assigns.current_scope.channel, socket.assigns.post, params) do
      {:ok, comment} -> {:noreply, socket |> stream_insert(:comments, Thicket.Repo.preload(comment, :channel), at: -1) |> assign(:comment_form, to_form(Comment.changeset(%Comment{}, %{})))}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Could not comment: #{inspect(reason)}")}
    end
  end

  def handle_event(action, %{"id" => _id}, socket) when action in ["like", "share"] do
    channel = socket.assigns.current_scope.channel
    result = if action == "like", do: Social.like(channel, socket.assigns.post), else: Social.share(channel, socket.assigns.post)
    {:noreply, if(match?({:ok, _}, result), do: put_flash(socket, :info, "Saved"), else: put_flash(socket, :error, "Could not save"))}
  end

  def handle_event("report", %{"report" => %{"reason" => reason}}, socket) do
    attrs = %{subject_type: :post, subject_id: socket.assigns.post.id, reason: reason}

    case Thicket.Moderation.report(socket.assigns.current_scope.channel, attrs) do
      {:ok, _} -> {:noreply, put_flash(socket, :info, "Report sent to the instance moderators")}
      {:error, changeset} -> {:noreply, put_flash(socket, :error, "Could not report: #{inspect(changeset.errors)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.post_card post={@post} current_scope={@current_scope} />
      <details :if={@current_scope} class="mt-4 rounded-xl border border-slate-200 bg-white p-4"><summary class="cursor-pointer text-sm text-slate-600">Report this post</summary><.form for={@report_form} id="report-form" phx-submit="report" class="mt-3 flex gap-3"><.input field={@report_form[:reason]} label="Reason" required /><.button class="btn">Send report</.button></.form></details>
      <section class="mt-10"><h2 class="mb-5 text-2xl font-bold">Comments</h2>
        <.form :if={@current_scope && !@post.comments_locked} for={@comment_form} id="comment-form" phx-submit="comment" class="mb-8 space-y-3">
          <.input field={@comment_form[:source]} type="textarea" label="Join the conversation" required />
          <.button class="btn btn-primary">Comment</.button>
        </.form>
        <p :if={@post.comments_locked} class="mb-6 rounded-xl bg-amber-50 p-4">Comments are locked.</p>
        <div id="comments" phx-update="stream" class="space-y-4">
          <article :for={{id, comment} <- @streams.comments} id={id} class="rounded-2xl border border-slate-200 bg-white p-5">
            <p class="mb-2 text-sm font-semibold">@{comment.channel.handle}</p>
            <%= if comment.deleted_at do %><p class="italic text-slate-400">Comment deleted</p><% else %><div>{Phoenix.HTML.raw(comment.rendered_html)}</div><% end %>
          </article>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
