defmodule Thicket.Repo.Migrations.AddChannelSigningKeys do
  use Ecto.Migration

  def change do
    create table(:channel_signing_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all),
        null: false

      add :public_key_pem, :text, null: false
      add :encrypted_private_key, :binary, null: false
      add :fingerprint, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:channel_signing_keys, [:channel_id])
    create unique_index(:channel_signing_keys, [:fingerprint])
  end
end
