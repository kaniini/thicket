defmodule Thicket.Federation.DeliveryTest do
  use Thicket.DataCase

  import Thicket.IdentityFixtures

  alias Thicket.Federation.{Delivery, Follows, RemoteActor}

  setup do
    Application.put_env(:thicket, :delivery_test_pid, self())
    Application.put_env(:thicket, :delivery_test_result, {:ok, 202})

    on_exit(fn ->
      Application.delete_env(:thicket, :delivery_test_pid)
      Application.delete_env(:thicket, :delivery_test_result)
    end)

    {:ok, user} = Thicket.Identity.register_invited_user(valid_registration_attributes())
    channel = user |> Thicket.Identity.list_channels() |> hd()
    remote = remote_actor_fixture()
    %{channel: channel, remote: remote}
  end

  test "durably delivers a signed Follow to the advertised shared inbox", %{
    channel: channel,
    remote: remote
  } do
    assert {:ok, %{delivery: delivery}} = Follows.follow(channel, remote)
    delivery = Repo.reload!(delivery)
    assert delivery.state == :delivered
    assert delivery.attempt_count == 1
    assert delivery.last_status == 202
    assert delivery.delivered_at

    assert_receive {:federation_delivery, "https://remote.example/inbox", headers, body}
    assert List.keyfind(headers, "signature", 0)
    assert Jason.decode!(body)["type"] == "Follow"

    {:ok, key} = Thicket.Federation.KeyStore.ensure_key(channel)

    assert {:ok, _key_id} =
             Thicket.Federation.HTTPSignature.verify(
               :post,
               "/inbox",
               headers,
               body,
               key.public_key_pem
             )
  end

  test "classifies temporary failures for bounded Oban retry", %{channel: channel, remote: remote} do
    Application.put_env(:thicket, :delivery_test_result, {:ok, 503})
    assert {:ok, %{delivery: delivery}} = Follows.follow(channel, remote)
    delivery = Repo.reload!(delivery)
    assert delivery.state == :retryable
    assert delivery.attempt_count == 1
    assert delivery.last_status == 503
  end

  test "classifies permanent remote failures without retry", %{channel: channel, remote: remote} do
    Application.put_env(:thicket, :delivery_test_result, {:ok, 404})
    assert {:ok, %{delivery: delivery}} = Follows.follow(channel, remote)
    delivery = Repo.reload!(delivery)
    assert delivery.state == :permanent_failure
    assert delivery.last_status == 404
  end

  test "suspends delivery to locally blocked domains before network access", %{
    channel: channel,
    remote: remote
  } do
    admin = user_fixture() |> Ecto.Changeset.change(admin: true) |> Repo.update!()

    assert {:ok, _} =
             Thicket.Moderation.put_domain_rule(admin, %{
               domain: "remote.example",
               action: :suspend,
               reason: "test"
             })

    assert {:ok, %{delivery: delivery}} = Follows.follow(channel, remote)
    assert Repo.reload!(delivery).state == :suspended
    refute_receive {:federation_delivery, _, _, _}
  end

  test "deduplicates a delivery by durable activity and inbox", %{
    channel: channel,
    remote: remote
  } do
    assert {:ok, %{delivery: delivery}} = Follows.follow(channel, remote)

    duplicate =
      %Delivery{activity_id: delivery.activity_id}
      |> Delivery.changeset(%{
        inbox_iri: delivery.inbox_iri,
        domain: delivery.domain,
        state: :pending
      })

    assert {:error, changeset} = Repo.insert(duplicate)
    assert "has already been taken" in errors_on(changeset).activity_id
  end

  defp remote_actor_fixture(iri \\ "https://remote.example/users/alice") do
    uri = URI.parse(iri)
    now = DateTime.utc_now(:second)

    Repo.insert!(%RemoteActor{
      canonical_iri: iri,
      actor_type: "Person",
      preferred_username: Path.basename(uri.path),
      inbox_iri: "#{iri}/inbox",
      shared_inbox_iri: "https://#{uri.host}/inbox",
      public_key_id: "#{iri}#main-key",
      public_key_pem: "public key",
      source_authority: uri.host,
      cache_state: :warm,
      fetched_at: now,
      validated_at: now,
      last_accessed_at: now
    })
  end
end
