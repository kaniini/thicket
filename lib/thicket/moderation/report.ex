defmodule Thicket.Moderation.Report do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "reports" do
    field :subject_type, Ecto.Enum, values: [:post, :comment, :channel]
    field :subject_id, :binary_id
    field :reason, :string
    field :state, Ecto.Enum, values: [:open, :resolved, :dismissed], default: :open
    field :resolved_at, :utc_datetime
    belongs_to :reporter_channel, Thicket.Identity.Channel
    belongs_to :resolved_by, Thicket.Identity.User
    timestamps(type: :utc_datetime)
  end

  def changeset(report, attrs) do
    report
    |> cast(attrs, [:subject_type, :subject_id, :reason])
    |> validate_required([:subject_type, :subject_id, :reason])
    |> validate_length(:reason, min: 3, max: 5_000)
  end
end
