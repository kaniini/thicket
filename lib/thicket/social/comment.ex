defmodule Thicket.Social.Comment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "comments" do
    field :source, :string
    field :rendered_html, :string
    field :deleted_at, :utc_datetime
    field :hidden_at, :utc_datetime
    belongs_to :post, Thicket.Social.Post
    belongs_to :parent, __MODULE__
    belongs_to :channel, Thicket.Identity.Channel
    has_many :children, __MODULE__, foreign_key: :parent_id
    timestamps(type: :utc_datetime)
  end

  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:source])
    |> validate_required([:source])
    |> validate_length(:source, min: 1, max: 20_000)
  end
end
