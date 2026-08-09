defmodule Thicket.Identity.Channel do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "channels" do
    field :handle, :string
    field :display_name, :string
    field :biography, :string, default: ""
    field :avatar_url, :string
    field :header_url, :string
    field :comments_default_locked, :boolean, default: false
    field :profile_links, :string, virtual: true
    has_many :memberships, Thicket.Identity.ChannelMembership
    has_many :links, Thicket.Identity.ChannelLink
    many_to_many :users, Thicket.Identity.User, join_through: Thicket.Identity.ChannelMembership
    timestamps(type: :utc_datetime)
  end

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [
      :handle,
      :display_name,
      :biography,
      :avatar_url,
      :header_url,
      :comments_default_locked,
      :profile_links
    ])
    |> update_change(:handle, &String.downcase/1)
    |> validate_required([:handle, :display_name])
    |> validate_format(:handle, ~r/^[a-z0-9][a-z0-9_-]{0,30}$/,
      message: "must start with a letter or number and contain only letters, numbers, _ or -"
    )
    |> validate_length(:display_name, min: 1, max: 80)
    |> validate_length(:biography, max: 5_000)
    |> unique_constraint(:handle)
  end
end
