defmodule Thicket.Social.CommentRevision do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "comment_revisions" do
    field :source, :string
    field :rendered_html, :string
    belongs_to :comment, Thicket.Social.Comment
    timestamps(type: :utc_datetime, updated_at: false)
  end
end
