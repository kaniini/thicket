defmodule Thicket.Moderation.DomainRule do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "domain_rules" do
    field :domain, :string
    field :action, Ecto.Enum, values: [:suspend]
    field :reason, :string
    belongs_to :created_by, Thicket.Identity.User
    timestamps(type: :utc_datetime)
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:domain, :action, :reason])
    |> update_change(:domain, &String.downcase/1)
    |> validate_required([:domain, :action])
    |> validate_format(:domain, ~r/^[a-z0-9.-]+$/)
    |> unique_constraint(:domain)
  end
end
