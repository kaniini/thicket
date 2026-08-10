defmodule Thicket.Federation.Inbox do
  @moduledoc "Idempotent, transactional processing for authenticated follow activities."

  import Ecto.Query

  alias Thicket.Federation.{
    Activity,
    Follows,
    InboxReceipt,
    RemoteActor,
    Serializer,
    StoredActivity
  }

  alias Thicket.Identity.Channel
  alias Thicket.Repo

  def process(%Activity{} = activity, %RemoteActor{} = actor, %Channel{} = target, body) do
    digest = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

    Repo.transaction(fn ->
      {inserted?, receipt} = reserve(activity, actor, target, digest)

      cond do
        receipt.body_digest != digest ->
          Repo.rollback(:activity_id_collision)

        not inserted? ->
          {:duplicate, receipt}

        true ->
          process_reserved(receipt, activity, actor, target)
      end
    end)
  end

  defp reserve(activity, actor, target, digest) do
    now = DateTime.utc_now(:second)

    row = %{
      id: Ecto.UUID.generate(),
      activity_iri: activity.id.value,
      actor_iri: actor.canonical_iri,
      body_digest: digest,
      state: :processing,
      target_channel_id: target.id,
      inserted_at: now,
      updated_at: now
    }

    case Repo.insert_all(InboxReceipt, [row],
           on_conflict: :nothing,
           conflict_target: [:activity_iri]
         ) do
      {0, _} -> {false, locked_receipt(activity.id.value)}
      {1, _} -> {true, locked_receipt(activity.id.value)}
    end
  end

  defp locked_receipt(activity_iri) do
    InboxReceipt
    |> where([receipt], receipt.activity_iri == ^activity_iri)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp process_reserved(receipt, activity, actor, target) do
    case store_inbound(activity, actor, target) do
      {:ok, stored} ->
        case normalize_result(Follows.handle(activity, actor, target)) do
          {:ok, result} ->
            receipt =
              receipt
              |> InboxReceipt.changeset(%{state: :accepted, stored_activity_id: stored.id})
              |> Repo.update!()

            {:accepted, receipt, result}

          {:error, reason} ->
            stored |> Ecto.Changeset.change(state: :rejected) |> Repo.update!()

            receipt =
              receipt
              |> InboxReceipt.changeset(%{
                state: :rejected,
                error_code: error_code(reason),
                stored_activity_id: stored.id
              })
              |> Repo.update!()

            {:rejected, receipt, reason}
        end

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp store_inbound(activity, actor, target) do
    %StoredActivity{}
    |> StoredActivity.changeset(%{
      activity_iri: activity.id.value,
      activity_type: activity.type,
      actor_iri: activity.actor.value,
      object_iri: object_iri(activity.object),
      payload: Serializer.to_map(activity),
      direction: :inbound,
      state: :processed,
      local_channel_id: target.id,
      remote_actor_id: actor.id
    })
    |> Repo.insert()
  end

  defp normalize_result({:ok, result}), do: {:ok, result}
  defp normalize_result({:error, reason}), do: {:error, reason}
  defp normalize_result({:error, _operation, reason, _changes}), do: {:error, reason}

  defp object_iri(%{value: value}), do: value
  defp object_iri(%Activity{id: %{value: value}}), do: value
  defp object_iri(_), do: nil
  defp error_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_code(_), do: "processing_failed"
end
