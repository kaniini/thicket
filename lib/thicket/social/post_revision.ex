defmodule Thicket.Social.PostRevision do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "post_revisions" do
    field :title, :string
    field :content_warning, :string
    field :source, :string
    field :source_format, Ecto.Enum, values: [:markdown, :html]
    field :rendered_html, :string
    field :render_version, :integer
    belongs_to :post, Thicket.Social.Post
    belongs_to :editor_channel, Thicket.Identity.Channel
    timestamps(type: :utc_datetime, updated_at: false)
  end
end
