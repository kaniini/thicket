defmodule Thicket.Repo.Migrations.EnforceNotificationUniqueness do
  use Ecto.Migration

  def change do
    create unique_index(
             :notifications,
             [:channel_id, :actor_channel_id, :kind, :subject_type, :subject_id],
             name: :notifications_semantic_key
           )
  end
end
