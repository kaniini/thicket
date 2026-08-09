defmodule Thicket.Social do
  @moduledoc "Local social domain. This context intentionally has no ActivityPub vocabulary."

  import Ecto.Query, warn: false
  alias Ecto.Multi
  alias Thicket.Identity.Channel
  alias Thicket.Repo
  alias Thicket.Rendering

  alias Thicket.Social.{
    Attachment,
    Comment,
    CommentRevision,
    Follow,
    Like,
    Notification,
    Post,
    PostRevision,
    Share
  }

  def change_post(%Post{} = post, attrs \\ %{}), do: Post.changeset(post, attrs)

  def create_post(%Channel{} = channel, attrs) do
    result =
      %Post{channel_id: channel.id, comments_locked: channel.comments_default_locked}
      |> Post.changeset(attrs)
      |> render_post()
      |> Repo.insert()

    case result do
      {:ok, post} ->
        notify_mentions(post, channel)
        {:ok, post}

      error ->
        error
    end
  end

  def update_post(%Channel{id: channel_id}, %Post{channel_id: channel_id} = post, attrs) do
    changeset = post |> Post.changeset(attrs) |> render_post()

    Multi.new()
    |> Multi.insert(:revision, revision_changeset(post, channel_id))
    |> Multi.update(:post, changeset)
    |> Repo.transaction()
    |> case do
      {:ok, %{post: post}} ->
        notify_mentions(post, %Channel{id: channel_id})
        {:ok, post}

      {:error, _operation, changeset, _changes} ->
        {:error, changeset}
    end
  end

  def update_post(%Channel{}, %Post{}, _attrs), do: {:error, :unauthorized}

  def publish_post(%Channel{} = channel, %Post{} = post) do
    update_post(channel, post, %{state: :published, published_at: DateTime.utc_now(:second)})
  end

  def delete_post(%Channel{id: channel_id}, %Post{channel_id: channel_id} = post) do
    post
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second))
    |> Repo.update()
  end

  def delete_post(%Channel{}, %Post{}), do: {:error, :unauthorized}

  def get_post!(id), do: Post |> preload([:channel, :attachments]) |> Repo.get!(id)

  def add_attachment(%Channel{id: channel_id}, %Post{channel_id: channel_id} = post, attrs) do
    %Attachment{post_id: post.id}
    |> Attachment.changeset(attrs)
    |> Repo.insert()
  end

  def add_attachment(%Channel{}, %Post{}, _attrs), do: {:error, :unauthorized}

  def list_channel_posts(%Channel{id: id}) do
    published_posts() |> where([p], p.channel_id == ^id) |> Repo.all()
  end

  def list_discovery_posts(limit \\ 40) do
    published_posts() |> limit(^limit) |> Repo.all()
  end

  def list_tag_posts(tag, limit \\ 40) when is_binary(tag) do
    if Regex.match?(~r/^[\p{L}\p{N}_-]{1,64}$/u, tag) do
      pattern = "(^|[^[:alnum:]_])##{tag}([^[:alnum:]_]|$)"

      published_posts()
      |> where([p], fragment("? ~* ?", p.source, ^pattern))
      |> limit(^limit)
      |> Repo.all()
    else
      []
    end
  end

  def list_home_posts(%Channel{id: channel_id}, limit \\ 40) do
    followed_ids =
      from(f in Follow,
        where: f.follower_channel_id == ^channel_id,
        select: f.followed_channel_id
      )

    blocked_ids = Thicket.Moderation.blocked_channel_ids(%Channel{id: channel_id})

    published_posts()
    |> where([p], p.channel_id == ^channel_id or p.channel_id in subquery(followed_ids))
    |> where([p], p.channel_id not in ^blocked_ids)
    |> limit(^limit)
    |> Repo.all()
  end

  def follow(%Channel{id: id}, %Channel{id: id}), do: {:error, :cannot_follow_self}

  def follow(%Channel{} = follower, %Channel{} = followed) do
    if Thicket.Moderation.blocked_between?(follower, followed) do
      {:error, :blocked}
    else
      Multi.new()
      |> Multi.insert(
        :follow,
        %Follow{follower_channel_id: follower.id, followed_channel_id: followed.id}
        |> Follow.changeset(%{})
      )
      |> maybe_notify(followed.id, follower.id, :follow, "channel", follower.id)
      |> Repo.transaction()
      |> unwrap_multi(:follow)
    end
  end

  def unfollow(%Channel{} = follower, %Channel{} = followed) do
    {count, _} =
      Repo.delete_all(
        from f in Follow,
          where: f.follower_channel_id == ^follower.id and f.followed_channel_id == ^followed.id
      )

    {:ok, count > 0}
  end

  def following?(%Channel{id: follower_id}, %Channel{id: followed_id}) do
    Repo.exists?(
      from f in Follow,
        where: f.follower_channel_id == ^follower_id and f.followed_channel_id == ^followed_id
    )
  end

  def like(%Channel{} = channel, %Post{} = post), do: react(Like, channel, post, :like)
  def share(%Channel{} = channel, %Post{} = post), do: react(Share, channel, post, :share)

  def unlike(%Channel{} = channel, %Post{} = post), do: unreact(Like, channel, post)
  def unshare(%Channel{} = channel, %Post{} = post), do: unreact(Share, channel, post)

  def create_comment(%Channel{} = channel, %Post{comments_locked: false} = post, attrs) do
    parent_id = Map.get(attrs, "parent_id") || Map.get(attrs, :parent_id)

    with false <- Thicket.Moderation.blocked_between_ids?(channel.id, post.channel_id),
         :ok <- validate_parent(post.id, parent_id),
         {:ok, html, _version} <-
           Rendering.render_comment(Map.get(attrs, "source") || Map.get(attrs, :source) || "") do
      comment = %Comment{
        post_id: post.id,
        parent_id: parent_id,
        channel_id: channel.id,
        rendered_html: html
      }

      Multi.new()
      |> Multi.insert(:comment, Comment.changeset(comment, attrs))
      |> Multi.run(:notification, fn repo, %{comment: comment} ->
        kind = if parent_id, do: :reply, else: :comment

        owner_id =
          if parent_id, do: repo.get!(Comment, parent_id).channel_id, else: post.channel_id

        insert_notification(repo, owner_id, channel.id, kind, "comment", comment.id)
      end)
      |> Repo.transaction()
      |> unwrap_multi(:comment)
    else
      true -> {:error, :blocked}
      error -> error
    end
  end

  def create_comment(%Channel{}, %Post{comments_locked: true}, _attrs),
    do: {:error, :comments_locked}

  def list_comments(%Post{id: post_id}) do
    comments =
      Comment
      |> where([c], c.post_id == ^post_id)
      |> order_by([c], asc: c.inserted_at, asc: c.id)
      |> preload(:channel)
      |> Repo.all()

    children = Enum.group_by(comments, & &1.parent_id)
    flatten_comment_children(children, nil)
  end

  def get_comment!(id), do: Comment |> preload(:channel) |> Repo.get!(id)

  def update_comment(%Channel{id: channel_id}, %Comment{channel_id: channel_id} = comment, attrs) do
    source = Map.get(attrs, "source") || Map.get(attrs, :source) || ""

    with {:ok, html, _version} <- Rendering.render_comment(source) do
      Multi.new()
      |> Multi.insert(
        :revision,
        Ecto.Changeset.change(%CommentRevision{}, %{
          comment_id: comment.id,
          source: comment.source,
          rendered_html: comment.rendered_html
        })
      )
      |> Multi.update(
        :comment,
        comment |> Comment.changeset(attrs) |> Ecto.Changeset.put_change(:rendered_html, html)
      )
      |> Repo.transaction()
      |> unwrap_multi(:comment)
    end
  end

  def update_comment(%Channel{}, %Comment{}, _attrs), do: {:error, :unauthorized}

  def delete_comment(%Channel{id: channel_id}, %Comment{channel_id: channel_id} = comment) do
    comment
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second), source: "", rendered_html: "")
    |> Repo.update()
  end

  def delete_comment(%Channel{}, %Comment{}), do: {:error, :unauthorized}

  def hide_comment(%Channel{id: channel_id}, %Post{channel_id: channel_id}, %Comment{} = comment) do
    comment |> Ecto.Changeset.change(hidden_at: DateTime.utc_now(:second)) |> Repo.update()
  end

  def hide_comment(%Channel{}, %Post{}, %Comment{}), do: {:error, :unauthorized}

  def set_comments_locked(%Channel{id: channel_id}, %Post{channel_id: channel_id} = post, locked?)
      when is_boolean(locked?) do
    post |> Ecto.Changeset.change(comments_locked: locked?) |> Repo.update()
  end

  def set_comments_locked(%Channel{}, %Post{}, _locked?), do: {:error, :unauthorized}

  def list_notifications(%Channel{id: channel_id}) do
    Notification
    |> where([n], n.channel_id == ^channel_id)
    |> order_by([n], desc: n.inserted_at)
    |> preload(:actor_channel)
    |> Repo.all()
  end

  defp render_post(changeset) do
    source = Ecto.Changeset.get_field(changeset, :source)
    format = Ecto.Changeset.get_field(changeset, :source_format)

    if changeset.valid? do
      case Rendering.render(source, format) do
        {:ok, html, version} ->
          changeset
          |> Ecto.Changeset.put_change(:rendered_html, html)
          |> Ecto.Changeset.put_change(:render_version, version)
          |> maybe_publish()

        {:error, _reason} ->
          Ecto.Changeset.add_error(changeset, :source, "could not be rendered")
      end
    else
      changeset
    end
  end

  defp maybe_publish(changeset) do
    if Ecto.Changeset.get_field(changeset, :state) == :published and
         is_nil(Ecto.Changeset.get_field(changeset, :published_at)) do
      Ecto.Changeset.put_change(changeset, :published_at, DateTime.utc_now(:microsecond))
    else
      changeset
    end
  end

  defp revision_changeset(post, editor_channel_id) do
    Ecto.Changeset.change(%PostRevision{}, %{
      post_id: post.id,
      editor_channel_id: editor_channel_id,
      title: post.title,
      content_warning: post.content_warning,
      source: post.source,
      source_format: post.source_format,
      rendered_html: post.rendered_html,
      render_version: post.render_version
    })
  end

  defp published_posts do
    Post
    |> where([p], p.state == :published and is_nil(p.deleted_at))
    |> order_by([p], desc: p.published_at, desc: p.id)
    |> preload([:channel, :attachments])
  end

  defp react(schema, channel, post, kind) do
    if Thicket.Moderation.blocked_between_ids?(channel.id, post.channel_id) do
      {:error, :blocked}
    else
      Repo.transaction(fn ->
        now = DateTime.utc_now(:second)

        {count, reactions} =
          Repo.insert_all(
            schema,
            [
              %{
                id: Ecto.UUID.generate(),
                channel_id: channel.id,
                post_id: post.id,
                inserted_at: now,
                updated_at: now
              }
            ],
            on_conflict: :nothing,
            conflict_target: [:channel_id, :post_id],
            returning: true
          )

        if count == 1 and post.channel_id != channel.id do
          notification(post.channel_id, channel.id, kind, "post", post.id) |> Repo.insert!()
        end

        List.first(reactions) || Repo.get_by!(schema, channel_id: channel.id, post_id: post.id)
      end)
    end
  end

  defp unreact(schema, channel, post) do
    {count, _} =
      Repo.delete_all(
        from r in schema, where: r.channel_id == ^channel.id and r.post_id == ^post.id
      )

    {:ok, count > 0}
  end

  defp notification(owner_id, actor_id, kind, type, id) do
    %Notification{channel_id: owner_id, actor_channel_id: actor_id}
    |> Notification.changeset(%{kind: kind, subject_type: type, subject_id: id})
  end

  defp maybe_notify(multi, owner_id, actor_id, _kind, _type, _id) when owner_id == actor_id,
    do: Multi.put(multi, :notification, :skipped)

  defp maybe_notify(multi, owner_id, actor_id, kind, type, id) do
    Multi.insert(multi, :notification, notification(owner_id, actor_id, kind, type, id),
      on_conflict: :nothing,
      conflict_target: [:channel_id, :actor_channel_id, :kind, :subject_type, :subject_id]
    )
  end

  defp insert_notification(_repo, owner_id, actor_id, _kind, _type, _id)
       when owner_id == actor_id,
       do: {:ok, :skipped}

  defp insert_notification(repo, owner_id, actor_id, kind, type, id) do
    repo.insert(notification(owner_id, actor_id, kind, type, id),
      on_conflict: :nothing,
      conflict_target: [:channel_id, :actor_channel_id, :kind, :subject_type, :subject_id]
    )
  end

  defp validate_parent(_post_id, nil), do: :ok

  defp validate_parent(post_id, parent_id) do
    if Repo.exists?(from c in Comment, where: c.id == ^parent_id and c.post_id == ^post_id),
      do: :ok,
      else: {:error, :invalid_parent}
  end

  defp unwrap_multi({:ok, values}, key), do: {:ok, Map.fetch!(values, key)}
  defp unwrap_multi({:error, _operation, reason, _changes}, _key), do: {:error, reason}

  defp flatten_comment_children(children, parent_id) do
    Enum.flat_map(Map.get(children, parent_id, []), fn comment ->
      [comment | flatten_comment_children(children, comment.id)]
    end)
  end

  defp notify_mentions(%Post{state: :published} = post, %Channel{} = actor) do
    Regex.scan(~r/(?:^|[^\w])@([a-zA-Z0-9][a-zA-Z0-9_-]{0,30})/, post.source,
      capture: :all_but_first
    )
    |> List.flatten()
    |> Enum.uniq_by(&String.downcase/1)
    |> Enum.each(fn handle ->
      case Thicket.Identity.get_channel_by_handle(handle) do
        %Channel{id: id} when id != actor.id ->
          notification(id, actor.id, :mention, "post", post.id)
          |> Repo.insert!(
            on_conflict: :nothing,
            conflict_target: [:channel_id, :actor_channel_id, :kind, :subject_type, :subject_id]
          )

        _ ->
          :ok
      end
    end)
  end

  defp notify_mentions(%Post{}, %Channel{}), do: :ok
end
