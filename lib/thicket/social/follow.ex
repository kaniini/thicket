defmodule Thicket.Social.Follow do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "follows" do
    field :state, Ecto.Enum, values: [:accepted], default: :accepted
    belongs_to :follower_channel, Thicket.Identity.Channel
    belongs_to :followed_channel, Thicket.Identity.Channel
    timestamps(type: :utc_datetime)
  end

  def changeset(follow, attrs) do
    follow
    |> cast(attrs, [])
    |> check_constraint(:followed_channel_id, name: :cannot_follow_self)
    |> unique_constraint([:follower_channel_id, :followed_channel_id])
  end
end
