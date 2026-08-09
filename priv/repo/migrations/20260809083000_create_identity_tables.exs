defmodule Thicket.Repo.Migrations.CreateIdentityTables do
  use Ecto.Migration

  def change do
    create table(:invitations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :secret_digest, :binary, null: false
      add :issuer_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :max_uses, :integer, null: false, default: 1
      add :redemption_count, :integer, null: false, default: 0
      add :expires_at, :utc_datetime
      add :revoked_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:invitations, [:secret_digest])
    create constraint(:invitations, :positive_max_uses, check: "max_uses > 0")

    create constraint(:invitations, :valid_redemption_count,
             check: "redemption_count >= 0 AND redemption_count <= max_uses"
           )

    create table(:channels, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :handle, :citext, null: false
      add :display_name, :string, null: false
      add :biography, :text, null: false, default: ""
      add :avatar_url, :string
      add :header_url, :string
      add :comments_default_locked, :boolean, null: false, default: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:channels, [:handle])

    create table(:channel_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all),
        null: false

      add :role, :string, null: false, default: "owner"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:channel_memberships, [:user_id, :channel_id])

    create unique_index(:channel_memberships, [:channel_id],
             where: "role = 'owner'",
             name: :one_owner_per_channel
           )

    create table(:channel_links, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all),
        null: false

      add :label, :string, null: false
      add :url, :string, null: false
      add :position, :integer, null: false, default: 0
      timestamps(type: :utc_datetime)
    end

    create index(:channel_links, [:channel_id, :position])
  end
end
