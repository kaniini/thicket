defmodule Thicket.Federation.SigningKey do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "channel_signing_keys" do
    field :public_key_pem, :string
    field :encrypted_private_key, :binary
    field :fingerprint, :string
    belongs_to :channel, Thicket.Identity.Channel
    timestamps(type: :utc_datetime)
  end

  def changeset(key, attrs) do
    key
    |> cast(attrs, [:public_key_pem, :encrypted_private_key, :fingerprint])
    |> validate_required([:channel_id, :public_key_pem, :encrypted_private_key, :fingerprint])
    |> unique_constraint(:channel_id)
    |> unique_constraint(:fingerprint)
  end
end
