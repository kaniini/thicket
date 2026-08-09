defmodule Thicket.Social.Share do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "shares" do
    belongs_to :channel, Thicket.Identity.Channel
    belongs_to :post, Thicket.Social.Post
    timestamps(type: :utc_datetime)
  end
end
