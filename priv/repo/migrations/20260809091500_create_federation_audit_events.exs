defmodule Thicket.Repo.Migrations.CreateFederationAuditEvents do
  use Ecto.Migration

  def change do
    create table(:federation_audit_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :direction, :string, null: false
      add :category, :string, null: false
      add :result, :string, null: false
      add :iri, :text
      add :domain, :string
      add :request_id, :string
      add :details, :map, null: false, default: %{}
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:federation_audit_events, [:inserted_at])
    create index(:federation_audit_events, [:domain, :inserted_at])
    create index(:federation_audit_events, [:category, :result])
  end
end
