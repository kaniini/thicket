defmodule Thicket.Identity.ChannelLink do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "channel_links" do
    field :label, :string
    field :url, :string
    field :position, :integer, default: 0
    belongs_to :channel, Thicket.Identity.Channel
    timestamps(type: :utc_datetime)
  end

  def changeset(link, attrs) do
    link
    |> cast(attrs, [:label, :url, :position])
    |> validate_required([:label, :url, :position])
    |> validate_length(:label, min: 1, max: 80)
    |> validate_length(:url, max: 2_000)
    |> validate_format(:url, ~r/^https:\/\//i, message: "must be an HTTPS URL")
  end
end
