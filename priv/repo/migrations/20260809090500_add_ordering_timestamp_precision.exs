defmodule Thicket.Repo.Migrations.AddOrderingTimestampPrecision do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      modify :published_at, :utc_datetime_usec
      modify :inserted_at, :utc_datetime_usec
      modify :updated_at, :utc_datetime_usec
    end

    alter table(:post_revisions), do: modify(:inserted_at, :utc_datetime_usec)

    alter table(:comments) do
      modify :inserted_at, :utc_datetime_usec
      modify :updated_at, :utc_datetime_usec
    end

    alter table(:comment_revisions), do: modify(:inserted_at, :utc_datetime_usec)

    alter table(:notifications) do
      modify :inserted_at, :utc_datetime_usec
      modify :updated_at, :utc_datetime_usec
    end
  end
end
