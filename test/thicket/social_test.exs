defmodule Thicket.SocialTest do
  use Thicket.DataCase, async: true

  alias Thicket.{Identity, Repo, Social}
  alias Thicket.Social.{CommentRevision, Like, PostRevision, Share}

  setup do
    user = Thicket.IdentityFixtures.user_fixture()
    {:ok, channel} = Identity.create_channel(user, %{handle: "author#{System.unique_integer([:positive])}", display_name: "Author"})
    %{user: user, channel: channel}
  end

  test "drafts stay private and publishing renders into discovery", %{channel: channel} do
    assert {:ok, draft} = Social.create_post(channel, %{source: "Hello **world**", source_format: :markdown, state: :draft})
    assert Social.list_discovery_posts() == []
    assert {:ok, published} = Social.publish_post(channel, draft)
    assert published.rendered_html =~ "<strong>world</strong>"
    assert [%{id: id}] = Social.list_discovery_posts()
    assert id == draft.id
  end

  test "edits retain the previous published representation", %{channel: channel} do
    {:ok, post} = Social.create_post(channel, %{source: "first", source_format: :markdown, state: :published})
    assert {:ok, updated} = Social.update_post(channel, post, %{source: "second"})
    assert updated.rendered_html =~ "second"
    assert [%{source: "first"}] = Repo.all(PostRevision)
  end

  test "another channel cannot modify or delete a post", %{channel: channel} do
    {:ok, post} = Social.create_post(channel, %{source: "mine", source_format: :markdown})
    other_user = Thicket.IdentityFixtures.user_fixture()
    {:ok, other} = Identity.create_channel(other_user, %{handle: "other#{System.unique_integer([:positive])}", display_name: "Other"})
    assert {:error, :unauthorized} = Social.update_post(other, post, %{source: "stolen"})
    assert {:error, :unauthorized} = Social.delete_post(other, post)
  end

  test "comments preserve direct parents, revisions, locking, deletion tombstones, and hiding", %{channel: author} do
    {:ok, post} = Social.create_post(author, %{source: "post", source_format: :markdown, state: :published})
    other_user = Thicket.IdentityFixtures.user_fixture()
    {:ok, commenter} = Identity.create_channel(other_user, %{handle: "commenter#{System.unique_integer([:positive])}", display_name: "Commenter"})
    assert {:ok, root} = Social.create_comment(commenter, post, %{source: "root"})
    assert {:ok, child} = Social.create_comment(commenter, post, %{source: "child", parent_id: root.id})
    assert child.parent_id == root.id
    assert {:ok, edited} = Social.update_comment(commenter, root, %{source: "edited"})
    assert edited.rendered_html =~ "edited"
    assert Repo.aggregate(CommentRevision, :count) == 1
    assert {:ok, hidden} = Social.hide_comment(author, post, child)
    assert hidden.hidden_at
    assert {:ok, deleted} = Social.delete_comment(commenter, edited)
    assert deleted.deleted_at && deleted.source == ""
    assert {:ok, locked} = Social.set_comments_locked(author, post, true)
    assert {:error, :comments_locked} = Social.create_comment(commenter, locked, %{source: "late"})
  end

  test "likes and shares are unique per channel and post", %{channel: channel} do
    {:ok, post} = Social.create_post(channel, %{source: "post", source_format: :markdown, state: :published})
    assert {:ok, _} = Social.like(channel, post)
    assert {:ok, _} = Social.like(channel, post)
    assert Repo.aggregate(Like, :count) == 1
    assert {:ok, _} = Social.share(channel, post)
    assert {:ok, _} = Social.share(channel, post)
    assert Repo.aggregate(Share, :count) == 1
  end
end
