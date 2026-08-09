defmodule ThicketWeb.PostLive.Show do
  use ThicketWeb, :live_view
  alias Thicket.Social
  alias Thicket.Social.Comment

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    post = Social.get_post!(id)

    if post.state == :published && is_nil(post.deleted_at) do
      comments = Social.list_comments(post)

      {:ok,
       socket
       |> assign(:post, post)
       |> assign(:reply_to, nil)
       |> assign(:comment_depths, comment_depths(comments))
       |> assign(:comment_form, to_form(Comment.changeset(%Comment{}, %{})))
       |> assign(:report_form, to_form(%{"reason" => ""}, as: :report))
       |> stream(:comments, comments)}
    else
      {:ok, socket |> put_flash(:error, "Post not found") |> push_navigate(to: ~p"/discover")}
    end
  end

  @impl true
  def handle_event("comment", %{"comment" => params}, socket) do
    case Social.create_comment(socket.assigns.current_scope.channel, socket.assigns.post, params) do
      {:ok, _comment} ->
        comments = Social.list_comments(socket.assigns.post)

        {:noreply,
         socket
         |> assign(:comment_depths, comment_depths(comments))
         |> stream(:comments, comments, reset: true)
         |> assign(:reply_to, nil)
         |> assign(:comment_form, to_form(Comment.changeset(%Comment{}, %{})))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not comment: #{inspect(reason)}")}
    end
  end

  def handle_event(action, %{"id" => _id}, socket)
      when action in ["like", "unlike", "share", "unshare"] do
    channel = socket.assigns.current_scope.channel

    result =
      case action do
        "like" -> Social.like(channel, socket.assigns.post)
        "unlike" -> Social.unlike(channel, socket.assigns.post)
        "share" -> Social.share(channel, socket.assigns.post)
        "unshare" -> Social.unshare(channel, socket.assigns.post)
      end

    {:noreply,
     if(match?({:ok, _}, result),
       do: put_flash(socket, :info, "Saved"),
       else: put_flash(socket, :error, "Could not save")
     )}
  end

  def handle_event("reply", %{"id" => id}, socket), do: {:noreply, assign(socket, :reply_to, id)}

  def handle_event("cancel-reply", _params, socket),
    do: {:noreply, assign(socket, :reply_to, nil)}

  def handle_event("delete-comment", %{"id" => id}, socket) do
    comment = Social.get_comment!(id)

    case Social.delete_comment(socket.assigns.current_scope.channel, comment) do
      {:ok, comment} ->
        {:noreply, stream_insert(socket, :comments, comment)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not delete: #{inspect(reason)}")}
    end
  end

  def handle_event("hide-comment", %{"id" => id}, socket) do
    comment = Social.get_comment!(id)

    case Social.hide_comment(socket.assigns.current_scope.channel, socket.assigns.post, comment) do
      {:ok, comment} ->
        {:noreply, stream_insert(socket, :comments, comment)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not hide: #{inspect(reason)}")}
    end
  end

  def handle_event(
        "edit-comment",
        %{"comment_id" => id, "edit_comment" => %{"source" => source}},
        socket
      ) do
    comment = Social.get_comment!(id)

    case Social.update_comment(socket.assigns.current_scope.channel, comment, %{source: source}) do
      {:ok, comment} ->
        {:noreply, stream_insert(socket, :comments, Thicket.Repo.preload(comment, :channel))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not edit: #{inspect(reason)}")}
    end
  end

  def handle_event("report", %{"report" => %{"reason" => reason}}, socket) do
    attrs = %{subject_type: :post, subject_id: socket.assigns.post.id, reason: reason}

    case Thicket.Moderation.report(socket.assigns.current_scope.channel, attrs) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, "Report sent to the instance moderators")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Could not report: #{inspect(changeset.errors)}")}
    end
  end

  defp comment_depths(comments) do
    Enum.reduce(comments, %{}, fn comment, depths ->
      depth = if comment.parent_id, do: Map.get(depths, comment.parent_id, 0) + 1, else: 0
      Map.put(depths, comment.id, depth)
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.post_card post={@post} current_scope={@current_scope} />
      <details :if={@current_scope} class="mt-4 rounded-xl border border-slate-200 bg-white p-4">
        <summary class="cursor-pointer text-sm text-slate-600">Report this post</summary>
        <.form for={@report_form} id="report-form" phx-submit="report" class="mt-3 flex gap-3">
          <.input field={@report_form[:reason]} label="Reason" required />
          <.button class="btn">
            Send report
          </.button>
        </.form>
      </details>
      <section class="mt-10">
        <h2 class="mb-5 text-2xl font-bold">Comments</h2>
        <.form
          :if={@current_scope && !@post.comments_locked}
          for={@comment_form}
          id="comment-form"
          phx-submit="comment"
          class="mb-8 space-y-3"
        >
          <input :if={@reply_to} type="hidden" name="comment[parent_id]" value={@reply_to} />
          <p :if={@reply_to} class="text-sm text-slate-500">
            Replying to a comment
            <button type="button" phx-click="cancel-reply" class="underline">Cancel</button>
          </p>
          <.input
            field={@comment_form[:source]}
            type="textarea"
            label="Join the conversation"
            required
          />
          <.button class="btn btn-primary">Comment</.button>
        </.form>
        <p :if={@post.comments_locked} class="mb-6 rounded-xl bg-amber-50 p-4">
          Comments are locked.
        </p>
        <div id="comments" phx-update="stream" class="space-y-4">
          <article
            :for={{id, comment} <- @streams.comments}
            id={id}
            class="rounded-2xl border border-slate-200 bg-white p-5"
            style={"margin-left: #{min(Map.get(@comment_depths, comment.id, 0), 6) * 1.25}rem"}
          >
            <p class="mb-2 text-sm font-semibold">@{comment.channel.handle}</p>
            <%= cond do %>
              <% comment.deleted_at -> %>
                <p class="italic text-slate-400">Comment deleted</p>
              <% comment.hidden_at && (!@current_scope || (@current_scope.channel.id != @post.channel_id && !@current_scope.user.admin)) -> %>
                <p class="italic text-slate-400">Comment hidden by moderation</p>
              <% true -> %>
                <div>{Phoenix.HTML.raw(comment.rendered_html)}</div>
            <% end %>
            <div
              :if={@current_scope && !comment.deleted_at}
              class="mt-3 flex gap-3 text-xs text-slate-500"
            >
              <button phx-click="reply" phx-value-id={comment.id}>Reply</button><button
                :if={@current_scope.channel.id == comment.channel_id}
                phx-click="delete-comment"
                phx-value-id={comment.id}
              >Delete</button><button
                :if={@current_scope.channel.id == @post.channel_id}
                phx-click="hide-comment"
                phx-value-id={comment.id}
              >Hide</button>
            </div>
            <.form
              :if={
                @current_scope && @current_scope.channel.id == comment.channel_id &&
                  !comment.deleted_at
              }
              for={to_form(%{"source" => comment.source}, as: :edit_comment)}
              id={"edit-comment-#{comment.id}"}
              phx-submit="edit-comment"
              class="mt-3"
            >
              <input type="hidden" name="comment_id" value={comment.id} /><.input
                field={to_form(%{"source" => comment.source}, as: :edit_comment)[:source]}
                label="Edit comment"
              /><.button class="btn">Save edit</.button>
            </.form>
          </article>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
