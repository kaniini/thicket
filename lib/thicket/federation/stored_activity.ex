defmodule Thicket.Federation.StoredActivity do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "federation_activities" do
    field :activity_iri, :string
    field :activity_type, :string
    field :actor_iri, :string
    field :object_iri, :string
    field :payload, :map
    field :direction, Ecto.Enum, values: [:inbound, :outbound]
    field :state, Ecto.Enum, values: [:pending, :processed, :rejected]
    belongs_to :local_channel, Thicket.Identity.Channel, type: :binary_id
    belongs_to :remote_actor, Thicket.Federation.RemoteActor, type: :binary_id
    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(activity, attrs) do
    activity
    |> cast(attrs, [
      :activity_iri,
      :activity_type,
      :actor_iri,
      :object_iri,
      :payload,
      :direction,
      :state,
      :local_channel_id,
      :remote_actor_id
    ])
    |> validate_required([
      :activity_iri,
      :activity_type,
      :actor_iri,
      :payload,
      :direction,
      :state
    ])
    |> unique_constraint(:activity_iri)
  end
end
