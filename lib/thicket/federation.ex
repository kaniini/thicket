defmodule Thicket.Federation do
  @moduledoc "Sovereign ActivityPub boundary and projections for Thicket."

  import Ecto.Query

  alias Thicket.Federation.{Actor, Collection, IRI, KeyStore, Object, PublicKey}
  alias Thicket.Identity.Channel
  alias Thicket.Repo
  alias Thicket.Social.{Follow, Post}

  def origin, do: ThicketWeb.Endpoint.url()
  def authority, do: URI.parse(origin()).authority

  def actor_iri(%Channel{handle: handle}), do: iri!("#{origin()}/ap/channels/#{handle}")
  def inbox_iri(channel), do: iri!("#{actor_iri(channel).value}/inbox")
  def outbox_iri(channel), do: iri!("#{actor_iri(channel).value}/outbox")
  def followers_iri(channel), do: iri!("#{actor_iri(channel).value}/followers")
  def following_iri(channel), do: iri!("#{actor_iri(channel).value}/following")
  def shared_inbox_iri, do: iri!("#{origin()}/ap/inbox")
  def post_iri(%Post{id: id}), do: iri!("#{origin()}/ap/posts/#{id}")

  def actor(%Channel{} = channel) do
    {:ok, key} = KeyStore.ensure_key(channel)
    actor_id = actor_iri(channel)

    %Actor{
      id: actor_id,
      type: "Person",
      preferred_username: channel.handle,
      name: channel.display_name,
      summary: channel.biography,
      inbox: inbox_iri(channel),
      outbox: outbox_iri(channel),
      followers: followers_iri(channel),
      following: following_iri(channel),
      shared_inbox: shared_inbox_iri(),
      public_key: %PublicKey{
        id: iri!("#{actor_id.value}#main-key"),
        owner: actor_id,
        public_key_pem: key.public_key_pem
      }
    }
  end

  def outbox(%Channel{} = channel) do
    %Collection{
      id: outbox_iri(channel),
      type: "OrderedCollection",
      total_items: 0,
      ordered_items: []
    }
  end

  def followers(%Channel{id: channel_id} = channel) do
    local_ids =
      Follow
      |> where([f], f.followed_channel_id == ^channel_id and f.state == :accepted)
      |> join(:inner, [f], c in Channel, on: c.id == f.follower_channel_id)
      |> order_by([f], asc: f.inserted_at)
      |> select([_f, c], c)
      |> Repo.all()
      |> Enum.map(&actor_iri/1)

    remote_ids =
      Follow
      |> where([f], f.followed_channel_id == ^channel_id and f.state == :accepted)
      |> join(:inner, [f], actor in Thicket.Federation.RemoteActor,
        on: actor.id == f.follower_remote_actor_id
      )
      |> order_by([f], asc: f.inserted_at)
      |> select([_f, actor], actor.canonical_iri)
      |> Repo.all()
      |> Enum.map(&iri!/1)

    ids = local_ids ++ remote_ids

    %Collection{
      id: followers_iri(channel),
      type: "OrderedCollection",
      total_items: length(ids),
      ordered_items: ids
    }
  end

  def following(%Channel{id: channel_id} = channel) do
    local_ids =
      Follow
      |> where([f], f.follower_channel_id == ^channel_id and f.state == :accepted)
      |> join(:inner, [f], c in Channel, on: c.id == f.followed_channel_id)
      |> order_by([f], asc: f.inserted_at)
      |> select([_f, c], c)
      |> Repo.all()
      |> Enum.map(&actor_iri/1)

    remote_ids =
      Follow
      |> where([f], f.follower_channel_id == ^channel_id and f.state == :accepted)
      |> join(:inner, [f], actor in Thicket.Federation.RemoteActor,
        on: actor.id == f.followed_remote_actor_id
      )
      |> order_by([f], asc: f.inserted_at)
      |> select([_f, actor], actor.canonical_iri)
      |> Repo.all()
      |> Enum.map(&iri!/1)

    ids = local_ids ++ remote_ids

    %Collection{
      id: following_iri(channel),
      type: "OrderedCollection",
      total_items: length(ids),
      ordered_items: ids
    }
  end

  def project_post(%Post{} = post, %Channel{} = channel) do
    public = iri!("https://www.w3.org/ns/activitystreams#Public")

    %Object{
      id: post_iri(post),
      type: if(post.title in [nil, ""], do: "Note", else: "Article"),
      attributed_to: actor_iri(channel),
      name: post.title,
      summary: post.content_warning,
      content: post.rendered_html,
      media_type: "text/html",
      source: %{
        content: post.source,
        media_type: if(post.source_format == :markdown, do: "text/markdown", else: "text/html")
      },
      published: format_datetime(post.published_at),
      recipients: %Thicket.Federation.Recipients{to: [public]}
    }
  end

  def get_public_post(id) do
    Post
    |> where([p], p.id == ^id and p.state == :published and is_nil(p.deleted_at))
    |> preload(:channel)
    |> Repo.one()
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(datetime), do: DateTime.to_iso8601(datetime)
  defp iri!(value), do: IRI.parse!(value)
end
