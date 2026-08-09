defmodule Thicket.Social.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "notifications" do
    field :kind, Ecto.Enum, values: [:follow, :like, :share, :comment, :reply, :mention]
    field :subject_type, :string
    field :subject_id, :binary_id
    field :read_at, :utc_datetime
    belongs_to :channel, Thicket.Identity.Channel
    belongs_to :actor_channel, Thicket.Identity.Channel
    timestamps(type: :utc_datetime)
  end

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:kind, :subject_type, :subject_id])
    |> validate_required([:kind, :subject_type, :subject_id])
  end
end
