defmodule Thicket.Repo.Migrations.CreateLocalSocialTables do
  use Ecto.Migration

  def change do
    create table(:posts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all), null: false
      add :title, :string
      add :content_warning, :string
      add :source, :text, null: false
      add :source_format, :string, null: false
      add :rendered_html, :text
      add :render_version, :integer
      add :state, :string, null: false, default: "draft"
      add :comments_locked, :boolean, null: false, default: false
      add :published_at, :utc_datetime
      add :deleted_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:posts, [:channel_id, :inserted_at])
    create index(:posts, [:state, :published_at])

    create table(:post_revisions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false
      add :editor_channel_id, references(:channels, type: :binary_id, on_delete: :nothing), null: false
      add :title, :string
      add :content_warning, :string
      add :source, :text, null: false
      add :source_format, :string, null: false
      add :rendered_html, :text
      add :render_version, :integer
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:post_revisions, [:post_id, :inserted_at])

    create table(:attachments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false
      add :storage_key, :string, null: false
      add :media_type, :string, null: false
      add :byte_size, :bigint, null: false
      add :description, :text, null: false
      add :position, :integer, null: false, default: 0
      timestamps(type: :utc_datetime)
    end

    create index(:attachments, [:post_id, :position])

    create table(:comments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false
      add :parent_id, references(:comments, type: :binary_id, on_delete: :nilify_all)
      add :channel_id, references(:channels, type: :binary_id, on_delete: :nothing), null: false
      add :source, :text, null: false
      add :rendered_html, :text, null: false
      add :deleted_at, :utc_datetime
      add :hidden_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:comments, [:post_id, :parent_id, :inserted_at])

    create table(:comment_revisions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :comment_id, references(:comments, type: :binary_id, on_delete: :delete_all), null: false
      add :source, :text, null: false
      add :rendered_html, :text, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create table(:follows, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :follower_channel_id, references(:channels, type: :binary_id, on_delete: :delete_all), null: false
      add :followed_channel_id, references(:channels, type: :binary_id, on_delete: :delete_all), null: false
      add :state, :string, null: false, default: "accepted"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:follows, [:follower_channel_id, :followed_channel_id])
    create constraint(:follows, :cannot_follow_self,
             check: "follower_channel_id <> followed_channel_id"
           )

    create table(:likes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all), null: false
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:likes, [:channel_id, :post_id])

    create table(:shares, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all), null: false
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:shares, [:channel_id, :post_id])

    create table(:notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all), null: false
      add :actor_channel_id, references(:channels, type: :binary_id, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :subject_type, :string, null: false
      add :subject_id, :binary_id, null: false
      add :read_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:notifications, [:channel_id, :inserted_at])

    create table(:blocks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :blocker_channel_id, references(:channels, type: :binary_id, on_delete: :delete_all), null: false
      add :blocked_channel_id, references(:channels, type: :binary_id, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:blocks, [:blocker_channel_id, :blocked_channel_id])

    create table(:domain_rules, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :domain, :citext, null: false
      add :action, :string, null: false
      add :reason, :text
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create unique_index(:domain_rules, [:domain])

    create table(:reports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :reporter_channel_id, references(:channels, type: :binary_id, on_delete: :nilify_all)
      add :subject_type, :string, null: false
      add :subject_id, :binary_id, null: false
      add :reason, :text, null: false
      add :state, :string, null: false, default: "open"
      add :resolved_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :resolved_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:reports, [:state, :inserted_at])

    create table(:audit_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :actor_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :action, :string, null: false
      add :subject_type, :string, null: false
      add :subject_id, :binary_id
      add :metadata, :map, null: false, default: %{}
      timestamps(type: :utc_datetime, updated_at: false)
    end
  end
end
