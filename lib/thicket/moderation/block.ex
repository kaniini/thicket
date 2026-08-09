defmodule Thicket.Moderation.Block do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "blocks" do
    belongs_to :blocker_channel, Thicket.Identity.Channel
    belongs_to :blocked_channel, Thicket.Identity.Channel
    timestamps(type: :utc_datetime)
  end
end
