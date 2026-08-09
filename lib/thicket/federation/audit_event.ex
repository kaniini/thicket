defmodule Thicket.Federation.AuditEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "federation_audit_events" do
    field :direction, Ecto.Enum, values: [:inbound, :outbound]
    field :category, :string
    field :result, Ecto.Enum, values: [:accepted, :rejected, :failed]
    field :iri, :string
    field :domain, :string
    field :request_id, :string
    field :details, :map, default: %{}
    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:direction, :category, :result, :iri, :domain, :request_id, :details])
    |> validate_required([:direction, :category, :result])
    |> validate_length(:category, max: 100)
    |> validate_length(:iri, max: 8_192)
    |> validate_length(:domain, max: 255)
    |> validate_length(:request_id, max: 255)
  end
end
