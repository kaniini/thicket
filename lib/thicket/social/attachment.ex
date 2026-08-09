defmodule Thicket.Social.Attachment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "attachments" do
    field :storage_key, :string
    field :media_type, :string
    field :byte_size, :integer
    field :description, :string
    field :position, :integer, default: 0
    belongs_to :post, Thicket.Social.Post
    timestamps(type: :utc_datetime)
  end

  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:storage_key, :media_type, :byte_size, :description, :position])
    |> validate_required([:storage_key, :media_type, :byte_size, :description])
    |> validate_inclusion(:media_type, ~w(image/avif image/gif image/jpeg image/png image/webp))
    |> validate_number(:byte_size, greater_than: 0, less_than_or_equal_to: 20_000_000)
    |> validate_length(:description, min: 1, max: 2_000)
  end
end
