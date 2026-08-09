defmodule Thicket.IdentityMilestoneTest do
  use Thicket.DataCase, async: true

  alias Thicket.Identity
  alias Thicket.Identity.Invitation
  alias Thicket.Repo

  test "operator invitations are hashed and atomically create the user and first channel" do
    {:ok, invitation, code} = Identity.create_operator_invitation(%{max_uses: 2})
    refute invitation.secret_digest == code
    assert invitation.secret_digest == :crypto.hash(:sha256, code)

    attrs = %{
      email: "new@example.com",
      invite_code: code,
      handle: "Garden_Path",
      display_name: "Garden Path"
    }

    assert {:ok, user} = Identity.register_invited_user(attrs)
    assert [%{handle: "garden_path"}] = Identity.list_channels(user)
    assert Repo.get!(Invitation, invitation.id).redemption_count == 1
  end

  test "expired, revoked, and fully redeemed invitations are rejected" do
    {:ok, invitation, code} = Identity.create_operator_invitation(%{max_uses: 1})
    attrs = %{email: "one@example.com", invite_code: code, handle: "one", display_name: "One"}
    assert {:ok, _user} = Identity.register_invited_user(attrs)

    assert {:error, %Ecto.Changeset{}} =
             Identity.register_invited_user(%{attrs | email: "two@example.com", handle: "two"})

    invitation
    |> Ecto.Changeset.change(redemption_count: 0, revoked_at: DateTime.utc_now(:second))
    |> Repo.update!()

    assert {:error, %Ecto.Changeset{}} =
             Identity.register_invited_user(%{
               attrs
               | email: "three@example.com",
                 handle: "three"
             })

    expired =
      invitation
      |> Ecto.Changeset.change(
        revoked_at: nil,
        expires_at: DateTime.add(DateTime.utc_now(:second), -1, :second)
      )
      |> Repo.update!()

    refute Invitation.available?(expired)
  end

  test "only administrators issue and revoke web invitations" do
    user = Thicket.IdentityFixtures.user_fixture()
    assert {:error, :unauthorized} = Identity.create_invitation(user)

    admin = user |> Ecto.Changeset.change(admin: true) |> Repo.update!()
    assert {:ok, invitation, _code} = Identity.create_invitation(admin, %{max_uses: 3})
    assert {:ok, revoked} = Identity.revoke_invitation(admin, invitation)
    assert revoked.revoked_at
  end

  test "channel authorization rejects another user's channel" do
    owner = Thicket.IdentityFixtures.user_fixture()
    outsider = Thicket.IdentityFixtures.user_fixture()

    assert {:ok, channel} =
             Identity.create_channel(owner, %{handle: "owner", display_name: "Owner"})

    assert_raise Ecto.NoResultsError, fn ->
      Identity.get_channel_for_user!(outsider, channel.id)
    end
  end

  test "channel profile links are replaced and restricted to HTTPS" do
    user = Thicket.IdentityFixtures.user_fixture()

    assert {:ok, channel} =
             Identity.create_channel(user, %{handle: "links", display_name: "Links"})

    assert {:ok, updated} =
             Identity.update_channel(user, channel, %{
               "profile_links" => "site https://example.com\nwork https://example.org"
             })

    assert Enum.map(updated.links, & &1.label) == ["site", "work"]

    assert {:error, %Ecto.Changeset{}} =
             Identity.update_channel(user, channel, %{"profile_links" => "bad http://example.com"})
  end
end
