defmodule Thicket.Moderation.AuditEvent do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "audit_events" do
    field :action, :string
    field :subject_type, :string
    field :subject_id, :binary_id
    field :metadata, :map, default: %{}
    belongs_to :actor_user, Thicket.Identity.User
    timestamps(type: :utc_datetime, updated_at: false)
  end
end
