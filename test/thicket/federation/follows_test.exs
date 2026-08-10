defmodule Thicket.Federation.FollowsTest do
  use Thicket.DataCase

  import Thicket.IdentityFixtures

  alias Thicket.Federation.{Activity, Follows, IRI, RemoteActor}
  alias Thicket.Social.Follow

  setup do
    {:ok, user} = Thicket.Identity.register_invited_user(valid_registration_attributes())
    channel = user |> Thicket.Identity.list_channels() |> hd()
    remote = remote_actor_fixture()
    %{channel: channel, remote: remote}
  end

  test "creates a pending outbound Follow and accepts its authorized response", %{
    channel: channel,
    remote: remote
  } do
    assert {:ok, %{activity: stored, follow: follow}} = Follows.follow(channel, remote)
    assert stored.activity_type == "Follow"
    assert stored.direction == :outbound
    assert follow.state == :pending
    assert follow.activity_iri == stored.activity_iri

    accept = remote_response("Accept", remote, channel, stored.activity_iri)
    assert {:ok, accepted} = Follows.handle(accept, remote, channel)
    assert accepted.state == :accepted
    assert accepted.response_activity_iri == accept.id.value

    following = Thicket.Federation.following(channel) |> Thicket.Federation.Serializer.to_map()
    assert remote.canonical_iri in following["orderedItems"]

    assert {:error, :follow, _changeset, _changes} = Follows.follow(channel, remote)
  end

  test "records rejection of an outbound Follow", %{channel: channel, remote: remote} do
    assert {:ok, %{activity: stored}} = Follows.follow(channel, remote)
    reject = remote_response("Reject", remote, channel, stored.activity_iri)
    assert {:ok, follow} = Follows.handle(reject, remote, channel)
    assert follow.state == :rejected
  end

  test "accepts an inbound Follow and creates a durable Accept", %{
    channel: channel,
    remote: remote
  } do
    follow = remote_follow(remote, channel)

    assert {:ok, %{follow: relationship, response: response}} =
             Follows.handle(follow, remote, channel)

    assert relationship.state == :accepted
    assert relationship.follower_remote_actor_id == remote.id
    assert relationship.followed_channel_id == channel.id
    assert response.activity_type == "Accept"
    assert response.payload["object"]["id"] == follow.id.value
    assert response.payload["object"]["type"] == "Follow"
  end

  test "undo removes only the authenticated actor's inbound Follow", %{
    channel: channel,
    remote: remote
  } do
    follow = remote_follow(remote, channel)
    assert {:ok, %{follow: relationship}} = Follows.handle(follow, remote, channel)

    undo = %Activity{
      id: iri("https://remote.example/activities/undo-1"),
      type: "Undo",
      actor: iri(remote.canonical_iri),
      object: follow.id
    }

    assert {:ok, :undone} = Follows.handle(undo, remote, channel)
    refute Repo.get(Follow, relationship.id)
  end

  test "local unfollow creates a durable Undo", %{channel: channel, remote: remote} do
    assert {:ok, %{activity: follow_activity}} = Follows.follow(channel, remote)
    assert {:ok, %{activity: undo}} = Follows.undo_follow(channel, remote)
    assert undo.activity_type == "Undo"
    assert undo.object_iri == follow_activity.activity_iri

    refute Repo.get_by(Follow,
             follower_channel_id: channel.id,
             followed_remote_actor_id: remote.id
           )
  end

  test "rejects actor and target confusion", %{channel: channel, remote: remote} do
    other = remote_actor_fixture("https://other.example/users/bob")
    follow = remote_follow(remote, channel)
    assert {:error, :actor_mismatch} = Follows.handle(follow, other, channel)

    wrong_target = %{follow | object: iri("https://local.example/not-this-channel")}
    assert {:error, :wrong_follow_target} = Follows.handle(wrong_target, remote, channel)
  end

  defp remote_follow(remote, channel) do
    %Activity{
      id: iri("https://remote.example/activities/follow-1"),
      type: "Follow",
      actor: iri(remote.canonical_iri),
      object: Thicket.Federation.actor_iri(channel)
    }
  end

  defp remote_response(type, remote, channel, followed_activity_iri) do
    %Activity{
      id: iri("https://remote.example/activities/#{String.downcase(type)}-1"),
      type: type,
      actor: iri(remote.canonical_iri),
      object: iri(followed_activity_iri),
      recipients: %Thicket.Federation.Recipients{to: [Thicket.Federation.actor_iri(channel)]}
    }
  end

  defp remote_actor_fixture(iri \\ "https://remote.example/users/alice") do
    now = DateTime.utc_now(:second)
    parsed = IRI.parse!(iri)

    Repo.insert!(%RemoteActor{
      canonical_iri: iri,
      actor_type: "Person",
      preferred_username: Path.basename(parsed.path),
      inbox_iri: "#{iri}/inbox",
      public_key_id: "#{iri}#main-key",
      public_key_pem: "public key",
      source_authority: parsed.host,
      cache_state: :warm,
      fetched_at: now,
      validated_at: now,
      last_accessed_at: now
    })
  end

  defp iri(value), do: IRI.parse!(value)
end
