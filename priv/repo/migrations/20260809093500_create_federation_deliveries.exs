defmodule Thicket.Repo.Migrations.CreateFederationDeliveries do
  use Ecto.Migration

  def change do
    create table(:federation_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :activity_id,
          references(:federation_activities, type: :binary_id, on_delete: :delete_all),
          null: false

      add :inbox_iri, :text, null: false
      add :domain, :string, null: false
      add :state, :string, null: false, default: "pending"
      add :attempt_count, :integer, null: false, default: 0
      add :last_status, :integer
      add :last_error, :string
      add :last_attempted_at, :utc_datetime
      add :delivered_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:federation_deliveries, [:activity_id, :inbox_iri])
    create index(:federation_deliveries, [:state, :inserted_at])
    create index(:federation_deliveries, [:domain, :state])
  end
end
