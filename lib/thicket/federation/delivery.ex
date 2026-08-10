defmodule Thicket.Federation.Delivery do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "federation_deliveries" do
    field :inbox_iri, :string
    field :domain, :string

    field :state, Ecto.Enum,
      values: [:pending, :retryable, :delivered, :permanent_failure, :suspended],
      default: :pending

    field :attempt_count, :integer, default: 0
    field :last_status, :integer
    field :last_error, :string
    field :last_attempted_at, :utc_datetime
    field :delivered_at, :utc_datetime
    belongs_to :activity, Thicket.Federation.StoredActivity, type: :binary_id
    timestamps(type: :utc_datetime)
  end

  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [
      :activity_id,
      :inbox_iri,
      :domain,
      :state,
      :attempt_count,
      :last_status,
      :last_error,
      :last_attempted_at,
      :delivered_at
    ])
    |> validate_required([:activity_id, :inbox_iri, :domain, :state])
    |> unique_constraint([:activity_id, :inbox_iri])
  end
end
