defmodule Thicket.Federation.DeliveryWorker do
  use Oban.Worker, queue: :default, max_attempts: 10

  alias Thicket.Federation.{Audit, Delivery, HTTPSignature, IRI, KeyStore}
  alias Thicket.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"delivery_id" => id}}) do
    delivery = Delivery |> Repo.get!(id) |> Repo.preload(activity: :local_channel)

    cond do
      delivery.state in [:delivered, :permanent_failure, :suspended] ->
        :ok

      Thicket.Moderation.domain_suspended?(delivery.domain) ->
        update(delivery, %{state: :suspended, last_error: "domain suspended"})
        :discard

      true ->
        attempt(delivery)
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    base = min(trunc(:math.pow(2, attempt)) * 15, 21_600)
    base + :rand.uniform(max(div(base, 4), 1))
  end

  defp attempt(delivery) do
    activity = delivery.activity
    channel = activity.local_channel
    body = Jason.encode!(activity.payload)
    inbox = IRI.parse!(delivery.inbox_iri)

    with {:ok, key} <- KeyStore.ensure_key(channel),
         {:ok, signed_headers} <-
           HTTPSignature.sign(
             :post,
             inbox,
             body,
             "#{Thicket.Federation.actor_iri(channel).value}#main-key",
             key
           ),
         {:ok, status} <- transport().post(delivery.inbox_iri, signed_headers, body) do
      classify(delivery, status)
    else
      {:error, reason} -> retry(delivery, reason, nil)
    end
  end

  defp classify(delivery, status) when status in 200..299 do
    now = DateTime.utc_now(:second)

    update(
      delivery,
      attempt_attrs(delivery, %{state: :delivered, last_status: status, delivered_at: now})
    )

    audit(delivery, :accepted, :delivered, status)
    :ok
  end

  defp classify(delivery, status) when status in [408, 425, 429] or status in 500..599,
    do: retry(delivery, "HTTP #{status}", status)

  defp classify(delivery, status) do
    update(
      delivery,
      attempt_attrs(delivery, %{
        state: :permanent_failure,
        last_status: status,
        last_error: "HTTP #{status}"
      })
    )

    audit(delivery, :failed, :permanent_failure, status)
    :discard
  end

  defp retry(delivery, reason, status) do
    update(
      delivery,
      attempt_attrs(delivery, %{
        state: :retryable,
        last_status: status,
        last_error: inspect(reason, printable_limit: 500)
      })
    )

    audit(delivery, :failed, :retryable, status)
    {:error, reason}
  end

  defp attempt_attrs(delivery, attrs) do
    Map.merge(attrs, %{
      attempt_count: delivery.attempt_count + 1,
      last_attempted_at: DateTime.utc_now(:second)
    })
  end

  defp update(delivery, attrs), do: delivery |> Delivery.changeset(attrs) |> Repo.update!()

  defp audit(delivery, result, code, status) do
    Audit.record(%{
      direction: :outbound,
      category: "delivery",
      result: result,
      iri: delivery.inbox_iri,
      domain: delivery.domain,
      details: %{code: code, status: status}
    })
  end

  defp transport do
    Application.get_env(
      :thicket,
      :federation_delivery_transport,
      Thicket.Federation.ReqDeliveryTransport
    )
  end
end
