defmodule Thicket.Identity.ChannelMembership do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "channel_memberships" do
    field :role, Ecto.Enum, values: [:owner, :editor], default: :owner
    belongs_to :user, Thicket.Identity.User
    belongs_to :channel, Thicket.Identity.Channel
    timestamps(type: :utc_datetime)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role])
    |> validate_required([:role])
    |> unique_constraint([:user_id, :channel_id])
    |> unique_constraint(:channel_id, name: :one_owner_per_channel)
  end
end
