defmodule Thicket.Repo.Migrations.CreateInboxReceipts do
  use Ecto.Migration

  def change do
    create table(:inbox_receipts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :activity_iri, :text, null: false
      add :actor_iri, :text, null: false
      add :body_digest, :string, null: false
      add :state, :string, null: false
      add :error_code, :string
      add :target_channel_id, references(:channels, type: :binary_id, on_delete: :nilify_all)

      add :stored_activity_id,
          references(:federation_activities, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:inbox_receipts, [:activity_iri])
    create index(:inbox_receipts, [:actor_iri, :inserted_at])
  end
end
