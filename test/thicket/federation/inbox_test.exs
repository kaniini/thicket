defmodule Thicket.Federation.InboxTest do
  use Thicket.DataCase

  import Thicket.IdentityFixtures

  alias Thicket.Federation.{Activity, Inbox, InboxReceipt, IRI, RemoteActor}
  alias Thicket.Social.Follow

  setup do
    {:ok, user} = Thicket.Identity.register_invited_user(valid_registration_attributes())
    channel = user |> Thicket.Identity.list_channels() |> hd()
    remote = remote_actor_fixture()
    activity = remote_follow(remote, channel)
    body = Thicket.Federation.Serializer.encode!(activity)
    %{channel: channel, remote: remote, activity: activity, body: body}
  end

  test "processes a Follow once and returns the durable receipt on replay", context do
    assert {:ok, {:accepted, receipt, _result}} =
             Inbox.process(context.activity, context.remote, context.channel, context.body)

    assert receipt.state == :accepted
    assert Repo.aggregate(InboxReceipt, :count) == 1
    assert Repo.aggregate(Follow, :count) == 1

    assert {:ok, {:duplicate, duplicate}} =
             Inbox.process(context.activity, context.remote, context.channel, context.body)

    assert duplicate.id == receipt.id
    assert Repo.aggregate(InboxReceipt, :count) == 1
    assert Repo.aggregate(Follow, :count) == 1
  end

  test "rejects reuse of an activity id with different bytes", context do
    assert {:ok, {:accepted, _, _}} =
             Inbox.process(context.activity, context.remote, context.channel, context.body)

    assert {:error, :activity_id_collision} =
             Inbox.process(context.activity, context.remote, context.channel, context.body <> " ")
  end

  test "retains rejected receipts without applying domain state", context do
    wrong = %{context.activity | object: IRI.parse!("https://local.example/wrong")}
    body = Thicket.Federation.Serializer.encode!(wrong)

    assert {:ok, {:rejected, receipt, :wrong_follow_target}} =
             Inbox.process(wrong, context.remote, context.channel, body)

    assert receipt.state == :rejected
    assert receipt.error_code == "wrong_follow_target"
    assert Repo.aggregate(Follow, :count) == 0
  end

  defp remote_follow(remote, channel) do
    %Activity{
      id: IRI.parse!("https://remote.example/activities/follow-inbox-1"),
      type: "Follow",
      actor: IRI.parse!(remote.canonical_iri),
      object: Thicket.Federation.actor_iri(channel)
    }
  end

  defp remote_actor_fixture do
    now = DateTime.utc_now(:second)

    Repo.insert!(%RemoteActor{
      canonical_iri: "https://remote.example/users/alice",
      actor_type: "Person",
      preferred_username: "alice",
      inbox_iri: "https://remote.example/users/alice/inbox",
      public_key_id: "https://remote.example/users/alice#main-key",
      public_key_pem: "public key",
      source_authority: "remote.example",
      cache_state: :warm,
      fetched_at: now,
      validated_at: now,
      last_accessed_at: now
    })
  end
end
