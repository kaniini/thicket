defmodule Thicket.Federation.Deliveries do
  @moduledoc "Durable delivery creation and attempt state transitions."

  alias Ecto.Multi
  alias Thicket.Federation.{Delivery, DeliveryWorker, IRI, RemoteActor}

  def add_to_multi(%Multi{} = multi, activity_id, %RemoteActor{} = actor, name \\ :delivery) do
    inbox = actor.shared_inbox_iri || actor.inbox_iri
    domain = IRI.parse!(inbox).host
    delivery = %Delivery{id: Ecto.UUID.generate(), activity_id: activity_id}

    multi
    |> Multi.insert(
      name,
      Delivery.changeset(delivery, %{inbox_iri: inbox, domain: domain, state: :pending})
    )
    |> Oban.insert(
      {name, :job},
      DeliveryWorker.new(%{delivery_id: delivery.id},
        unique: [period: :infinity, fields: [:args]]
      )
    )
  end
end
