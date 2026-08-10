defmodule Thicket.Social.Follow do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "follows" do
    field :state, Ecto.Enum, values: [:pending, :accepted, :rejected], default: :accepted
    field :activity_iri, :string
    field :response_activity_iri, :string
    belongs_to :follower_channel, Thicket.Identity.Channel
    belongs_to :followed_channel, Thicket.Identity.Channel
    belongs_to :follower_remote_actor, Thicket.Federation.RemoteActor
    belongs_to :followed_remote_actor, Thicket.Federation.RemoteActor
    timestamps(type: :utc_datetime)
  end

  def changeset(follow, attrs) do
    follow
    |> cast(attrs, [:state, :activity_iri, :response_activity_iri])
    |> check_constraint(:follower_channel_id, name: :one_follower_identity)
    |> check_constraint(:followed_channel_id, name: :one_followed_identity)
    |> check_constraint(:followed_channel_id, name: :cannot_follow_self)
    |> unique_constraint([:follower_channel_id, :followed_channel_id],
      name: :follows_local_local_unique
    )
    |> unique_constraint([:follower_channel_id, :followed_remote_actor_id],
      name: :follows_local_remote_unique
    )
    |> unique_constraint([:follower_remote_actor_id, :followed_channel_id],
      name: :follows_remote_local_unique
    )
    |> unique_constraint(:activity_iri)
  end
end
