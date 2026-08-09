defmodule Thicket.ModerationTest do
  use Thicket.DataCase, async: true

  alias Thicket.{Identity, Moderation, Repo}
  alias Thicket.Moderation.AuditEvent

  setup do
    user = Thicket.IdentityFixtures.user_fixture()
    other = Thicket.IdentityFixtures.user_fixture()
    {:ok, channel} = Identity.create_channel(user, %{handle: "mod#{System.unique_integer([:positive])}", display_name: "Mod"})
    {:ok, target} = Identity.create_channel(other, %{handle: "target#{System.unique_integer([:positive])}", display_name: "Target"})
    %{user: user, channel: channel, target: target}
  end

  test "channels can block and unblock another channel", %{channel: channel, target: target} do
    assert {:ok, _} = Moderation.block(channel, target)
    assert Moderation.blocked?(channel, target)
    assert :ok = Moderation.unblock(channel, target)
    refute Moderation.blocked?(channel, target)
    assert {:error, :cannot_block_self} = Moderation.block(channel, channel)
  end

  test "reports require an administrator to resolve and create an audit event", %{user: user, channel: channel, target: target} do
    assert {:ok, report} = Moderation.report(channel, %{subject_type: :channel, subject_id: target.id, reason: "harassment"})
    assert {:error, :unauthorized} = Moderation.list_open_reports(user)
    admin = user |> Ecto.Changeset.change(admin: true) |> Repo.update!()
    assert [_] = Moderation.list_open_reports(admin)
    assert {:ok, %{report: resolved}} = Moderation.resolve_report(admin, report, :resolved)
    assert resolved.state == :resolved
    assert Repo.aggregate(AuditEvent, :count) == 1
  end
end
