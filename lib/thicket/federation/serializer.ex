defmodule Thicket.Federation.Serializer do
  @moduledoc "Deterministic serialization for supported typed ActivityStreams values."

  alias Thicket.Federation.{Activity, Actor, Collection, IRI, Object, PublicKey, Recipients}

  @context "https://www.w3.org/ns/activitystreams"

  def encode(value), do: value |> to_map() |> Jason.encode()
  def encode!(value), do: value |> to_map() |> Jason.encode!()

  def to_map(%Actor{} = actor) do
    actor.extensions
    |> Map.merge(%{
      "@context" => @context,
      "id" => iri(actor.id),
      "type" => actor.type,
      "preferredUsername" => actor.preferred_username,
      "name" => actor.name,
      "summary" => actor.summary,
      "inbox" => iri(actor.inbox),
      "outbox" => iri(actor.outbox),
      "followers" => iri(actor.followers),
      "following" => iri(actor.following),
      "endpoints" => if(actor.shared_inbox, do: %{"sharedInbox" => iri(actor.shared_inbox)}),
      "publicKey" => public_key(actor.public_key)
    })
    |> compact()
  end

  def to_map(%Activity{} = activity) do
    activity.extensions
    |> Map.merge(%{
      "@context" => @context,
      "id" => iri(activity.id),
      "type" => activity.type,
      "actor" => iri(activity.actor),
      "object" => object(activity.object),
      "published" => activity.published
    })
    |> recipients(activity.recipients)
    |> compact()
  end

  def to_map(%Object{} = object) do
    object.extensions
    |> Map.merge(%{
      "@context" => @context,
      "id" => iri(object.id),
      "type" => object.type,
      "attributedTo" => iri(object.attributed_to),
      "name" => object.name,
      "summary" => object.summary,
      "content" => object.content,
      "mediaType" => object.media_type,
      "source" => source(object.source),
      "inReplyTo" => iri(object.in_reply_to),
      "published" => object.published,
      "updated" => object.updated
    })
    |> recipients(object.recipients)
    |> compact()
  end

  def to_map(%Collection{} = collection) do
    %{
      "@context" => @context,
      "id" => iri(collection.id),
      "type" => collection.type,
      "totalItems" => collection.total_items,
      "first" => iri(collection.first),
      "next" => iri(collection.next),
      "prev" => iri(collection.prev),
      "orderedItems" => Enum.map(collection.ordered_items, &object/1),
      "items" => Enum.map(collection.items, &object/1)
    }
    |> compact()
  end

  defp recipients(map, %Recipients{} = recipients) do
    Enum.reduce(
      [
        to: recipients.to,
        cc: recipients.cc,
        bto: recipients.bto,
        bcc: recipients.bcc,
        audience: recipients.audience
      ],
      map,
      fn
        {_key, []}, acc -> acc
        {key, values}, acc -> Map.put(acc, Atom.to_string(key), Enum.map(values, &iri/1))
      end
    )
  end

  defp object(%IRI{} = value), do: iri(value)
  defp object(%_{} = value), do: to_map(value)
  defp object(value), do: value

  defp public_key(nil), do: nil

  defp public_key(%PublicKey{} = key) do
    %{"id" => iri(key.id), "owner" => iri(key.owner), "publicKeyPem" => key.public_key_pem}
  end

  defp source(nil), do: nil

  defp source(%{content: content, media_type: media_type}),
    do: %{"content" => content, "mediaType" => media_type}

  defp iri(nil), do: nil
  defp iri(%IRI{value: value}), do: value
  defp compact(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) or value == [] end)
end
