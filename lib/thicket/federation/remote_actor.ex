defmodule Thicket.Federation.RemoteActor do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "remote_actors" do
    field :canonical_iri, :string
    field :actor_type, :string
    field :preferred_username, :string
    field :name, :string
    field :summary, :string
    field :inbox_iri, :string
    field :outbox_iri, :string
    field :followers_iri, :string
    field :following_iri, :string
    field :shared_inbox_iri, :string
    field :public_key_id, :string
    field :public_key_pem, :string
    field :source_authority, :string
    field :etag, :string
    field :last_modified, :string
    field :normalized_document, :map
    field :cache_state, Ecto.Enum, values: [:warm, :cold], default: :warm
    field :fetched_at, :utc_datetime
    field :validated_at, :utc_datetime
    field :last_accessed_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(actor, attrs) do
    actor
    |> cast(attrs, [
      :canonical_iri,
      :actor_type,
      :preferred_username,
      :name,
      :summary,
      :inbox_iri,
      :outbox_iri,
      :followers_iri,
      :following_iri,
      :shared_inbox_iri,
      :public_key_id,
      :public_key_pem,
      :source_authority,
      :etag,
      :last_modified,
      :normalized_document,
      :cache_state,
      :fetched_at,
      :validated_at,
      :last_accessed_at
    ])
    |> validate_required([
      :canonical_iri,
      :actor_type,
      :inbox_iri,
      :source_authority,
      :cache_state,
      :fetched_at,
      :validated_at,
      :last_accessed_at
    ])
    |> unique_constraint(:canonical_iri)
  end
end
