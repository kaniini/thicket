defmodule Thicket.Repo.Migrations.AddFederatedFollows do
  use Ecto.Migration

  def up do
    create table(:federation_activities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :activity_iri, :text, null: false
      add :activity_type, :string, null: false
      add :actor_iri, :text, null: false
      add :object_iri, :text
      add :payload, :map, null: false
      add :direction, :string, null: false
      add :state, :string, null: false
      add :local_channel_id, references(:channels, type: :binary_id, on_delete: :nilify_all)
      add :remote_actor_id, references(:remote_actors, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:federation_activities, [:activity_iri])
    create index(:federation_activities, [:local_channel_id, :inserted_at])
    create index(:federation_activities, [:remote_actor_id, :inserted_at])

    drop unique_index(:follows, [:follower_channel_id, :followed_channel_id])
    drop constraint(:follows, :cannot_follow_self)

    alter table(:follows) do
      modify :follower_channel_id, :binary_id, null: true
      modify :followed_channel_id, :binary_id, null: true

      add :follower_remote_actor_id,
          references(:remote_actors, type: :binary_id, on_delete: :delete_all)

      add :followed_remote_actor_id,
          references(:remote_actors, type: :binary_id, on_delete: :delete_all)

      add :activity_iri, :text
      add :response_activity_iri, :text
    end

    create constraint(:follows, :one_follower_identity,
             check:
               "(follower_channel_id IS NOT NULL)::int + (follower_remote_actor_id IS NOT NULL)::int = 1"
           )

    create constraint(:follows, :one_followed_identity,
             check:
               "(followed_channel_id IS NOT NULL)::int + (followed_remote_actor_id IS NOT NULL)::int = 1"
           )

    create constraint(:follows, :cannot_follow_self,
             check:
               "follower_channel_id IS NULL OR followed_channel_id IS NULL OR follower_channel_id <> followed_channel_id"
           )

    create unique_index(:follows, [:follower_channel_id, :followed_channel_id],
             where: "follower_channel_id IS NOT NULL AND followed_channel_id IS NOT NULL",
             name: :follows_local_local_unique
           )

    create unique_index(:follows, [:follower_channel_id, :followed_remote_actor_id],
             where: "follower_channel_id IS NOT NULL AND followed_remote_actor_id IS NOT NULL",
             name: :follows_local_remote_unique
           )

    create unique_index(:follows, [:follower_remote_actor_id, :followed_channel_id],
             where: "follower_remote_actor_id IS NOT NULL AND followed_channel_id IS NOT NULL",
             name: :follows_remote_local_unique
           )

    create unique_index(:follows, [:activity_iri], where: "activity_iri IS NOT NULL")
  end

  def down do
    drop table(:federation_activities)
    drop index(:follows, [:activity_iri])
    drop index(:follows, name: :follows_remote_local_unique)
    drop index(:follows, name: :follows_local_remote_unique)
    drop index(:follows, name: :follows_local_local_unique)
    drop constraint(:follows, :one_follower_identity)
    drop constraint(:follows, :one_followed_identity)
    drop constraint(:follows, :cannot_follow_self)

    alter table(:follows) do
      remove :response_activity_iri
      remove :activity_iri
      remove :followed_remote_actor_id
      remove :follower_remote_actor_id
      modify :followed_channel_id, :binary_id, null: false
      modify :follower_channel_id, :binary_id, null: false
    end

    create unique_index(:follows, [:follower_channel_id, :followed_channel_id])

    create constraint(:follows, :cannot_follow_self,
             check: "follower_channel_id <> followed_channel_id"
           )
  end
end
