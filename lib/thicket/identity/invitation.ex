defmodule Thicket.Identity.Invitation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "invitations" do
    field :secret_digest, :binary, redact: true
    field :max_uses, :integer, default: 1
    field :redemption_count, :integer, default: 0
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime
    belongs_to :issuer, Thicket.Identity.User
    timestamps(type: :utc_datetime)
  end

  def create_changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:max_uses, :expires_at])
    |> validate_required([:secret_digest, :max_uses])
    |> validate_number(:max_uses, greater_than: 0)
    |> unique_constraint(:secret_digest)
  end

  def available?(invitation, now \\ DateTime.utc_now(:second)) do
    is_nil(invitation.revoked_at) and invitation.redemption_count < invitation.max_uses and
      (is_nil(invitation.expires_at) or DateTime.after?(invitation.expires_at, now))
  end
end
