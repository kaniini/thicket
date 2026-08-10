defmodule Thicket.Repo.Migrations.CreateRemoteActors do
  use Ecto.Migration

  def change do
    create table(:remote_actors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :canonical_iri, :text, null: false
      add :actor_type, :string
      add :preferred_username, :string
      add :name, :string
      add :summary, :text
      add :inbox_iri, :text
      add :outbox_iri, :text
      add :followers_iri, :text
      add :following_iri, :text
      add :shared_inbox_iri, :text
      add :public_key_id, :text
      add :public_key_pem, :text
      add :source_authority, :string, null: false
      add :etag, :string
      add :last_modified, :string
      add :normalized_document, :map
      add :cache_state, :string, null: false, default: "warm"
      add :fetched_at, :utc_datetime, null: false
      add :validated_at, :utc_datetime, null: false
      add :last_accessed_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:remote_actors, [:canonical_iri])
    create index(:remote_actors, [:source_authority])
    create index(:remote_actors, [:cache_state, :last_accessed_at])
  end
end
