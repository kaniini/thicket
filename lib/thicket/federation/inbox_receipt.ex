defmodule Thicket.Federation.InboxReceipt do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "inbox_receipts" do
    field :activity_iri, :string
    field :actor_iri, :string
    field :body_digest, :string
    field :state, Ecto.Enum, values: [:processing, :accepted, :rejected]
    field :error_code, :string
    belongs_to :target_channel, Thicket.Identity.Channel, type: :binary_id
    belongs_to :stored_activity, Thicket.Federation.StoredActivity, type: :binary_id
    timestamps(type: :utc_datetime)
  end

  def changeset(receipt, attrs) do
    receipt
    |> cast(attrs, [
      :activity_iri,
      :actor_iri,
      :body_digest,
      :state,
      :error_code,
      :target_channel_id,
      :stored_activity_id
    ])
    |> validate_required([:activity_iri, :actor_iri, :body_digest, :state])
    |> unique_constraint(:activity_iri)
  end
end
