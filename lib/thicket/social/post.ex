defmodule Thicket.Social.Post do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "posts" do
    field :title, :string
    field :content_warning, :string
    field :source, :string
    field :source_format, Ecto.Enum, values: [:markdown, :html]
    field :rendered_html, :string
    field :render_version, :integer
    field :state, Ecto.Enum, values: [:draft, :published], default: :draft
    field :comments_locked, :boolean, default: false
    field :published_at, :utc_datetime
    field :deleted_at, :utc_datetime
    field :attachment_descriptions, :string, virtual: true
    belongs_to :channel, Thicket.Identity.Channel
    has_many :comments, Thicket.Social.Comment
    has_many :attachments, Thicket.Social.Attachment
    timestamps(type: :utc_datetime)
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [:title, :content_warning, :source, :source_format, :state, :comments_locked, :attachment_descriptions])
    |> validate_required([:source, :source_format, :state])
    |> validate_length(:title, max: 200)
    |> validate_length(:content_warning, max: 500)
    |> validate_length(:source, min: 1, max: 250_000)
  end
end
