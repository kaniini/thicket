defmodule Thicket.Federation.Follows do
  @moduledoc "Federated follow state transitions, independent of HTTP delivery."

  alias Ecto.Multi
  alias Thicket.Federation.{Activity, IRI, RemoteActor, Serializer, StoredActivity}
  alias Thicket.Identity.Channel
  alias Thicket.Repo
  alias Thicket.Social.Follow

  def follow(%Channel{} = channel, %RemoteActor{cache_state: :warm} = remote_actor) do
    activity = follow_activity(channel, remote_actor)

    Multi.new()
    |> Multi.insert(:activity, stored(activity, channel, remote_actor, :outbound, :pending))
    |> Multi.insert(
      :follow,
      %Follow{follower_channel_id: channel.id, followed_remote_actor_id: remote_actor.id}
      |> Follow.changeset(%{state: :pending, activity_iri: activity.id.value})
    )
    |> Repo.transaction()
  end

  def follow(%Channel{}, %RemoteActor{}), do: {:error, :remote_actor_unavailable}

  def undo_follow(%Channel{id: channel_id} = channel, %RemoteActor{id: remote_id} = remote_actor) do
    case Repo.get_by(Follow, follower_channel_id: channel_id, followed_remote_actor_id: remote_id) do
      nil -> {:error, :not_following}
      follow -> create_undo(channel, remote_actor, follow)
    end
  end

  def handle(%Activity{type: "Follow"} = activity, %RemoteActor{} = actor, %Channel{} = target),
    do: inbound_follow(activity, actor, target)

  def handle(%Activity{type: type} = activity, %RemoteActor{} = actor, %Channel{} = target)
      when type in ["Accept", "Reject"],
      do: inbound_response(activity, actor, target)

  def handle(%Activity{type: "Undo"} = activity, %RemoteActor{} = actor, %Channel{} = target),
    do: inbound_undo(activity, actor, target)

  def handle(%Activity{}, %RemoteActor{}, %Channel{}), do: {:error, :unsupported_follow_activity}

  defp inbound_follow(activity, actor, target) do
    with :ok <- actor_matches(activity, actor),
         %IRI{value: object_iri} <- activity.object,
         true <- object_iri == Thicket.Federation.actor_iri(target).value do
      response = response_activity("Accept", target, actor, activity)

      Multi.new()
      |> Multi.insert(
        :follow,
        %Follow{follower_remote_actor_id: actor.id, followed_channel_id: target.id}
        |> Follow.changeset(%{
          state: :accepted,
          activity_iri: activity.id.value,
          response_activity_iri: response.id.value
        })
      )
      |> Multi.insert(:response, stored(response, target, actor, :outbound, :pending))
      |> Repo.transaction()
    else
      false -> {:error, :wrong_follow_target}
      nil -> {:error, :invalid_follow_object}
      error -> error
    end
  end

  defp inbound_response(activity, actor, target) do
    with :ok <- actor_matches(activity, actor),
         {:ok, object_iri} <- referenced_activity_iri(activity.object),
         %Follow{} = follow <-
           Repo.get_by(Follow,
             follower_channel_id: target.id,
             followed_remote_actor_id: actor.id,
             activity_iri: object_iri
           ) do
      state = if activity.type == "Accept", do: :accepted, else: :rejected

      follow
      |> Follow.changeset(%{state: state, response_activity_iri: activity.id.value})
      |> Repo.update()
    else
      nil -> {:error, :unknown_follow}
      error -> error
    end
  end

  defp inbound_undo(activity, actor, target) do
    with :ok <- actor_matches(activity, actor),
         {:ok, object_iri} <- referenced_activity_iri(activity.object),
         %Follow{} = follow <-
           Repo.get_by(Follow,
             follower_remote_actor_id: actor.id,
             followed_channel_id: target.id,
             activity_iri: object_iri
           ),
         {:ok, _} <- Repo.delete(follow) do
      {:ok, :undone}
    else
      nil -> {:error, :unknown_follow}
      error -> error
    end
  end

  defp create_undo(channel, remote_actor, follow) do
    actor_iri = Thicket.Federation.actor_iri(channel)
    activity_iri = activity_iri()

    undo = %Activity{
      id: activity_iri,
      type: "Undo",
      actor: actor_iri,
      object: IRI.parse!(follow.activity_iri),
      published: now_iso8601(),
      recipients: %Thicket.Federation.Recipients{to: [IRI.parse!(remote_actor.canonical_iri)]}
    }

    Multi.new()
    |> Multi.insert(:activity, stored(undo, channel, remote_actor, :outbound, :pending))
    |> Multi.delete(:follow, follow)
    |> Repo.transaction()
  end

  defp follow_activity(channel, remote_actor) do
    %Activity{
      id: activity_iri(),
      type: "Follow",
      actor: Thicket.Federation.actor_iri(channel),
      object: IRI.parse!(remote_actor.canonical_iri),
      published: now_iso8601(),
      recipients: %Thicket.Federation.Recipients{to: [IRI.parse!(remote_actor.canonical_iri)]}
    }
  end

  defp response_activity(type, channel, remote_actor, followed_activity) do
    %Activity{
      id: activity_iri(),
      type: type,
      actor: Thicket.Federation.actor_iri(channel),
      object: followed_activity,
      published: now_iso8601(),
      recipients: %Thicket.Federation.Recipients{to: [IRI.parse!(remote_actor.canonical_iri)]}
    }
  end

  defp stored(activity, channel, remote_actor, direction, state) do
    %StoredActivity{}
    |> StoredActivity.changeset(%{
      activity_iri: activity.id.value,
      activity_type: activity.type,
      actor_iri: activity.actor.value,
      object_iri: object_iri(activity.object),
      payload: Serializer.to_map(activity),
      direction: direction,
      state: state,
      local_channel_id: channel.id,
      remote_actor_id: remote_actor.id
    })
  end

  defp actor_matches(%Activity{actor: %IRI{value: iri}}, %RemoteActor{canonical_iri: iri}),
    do: :ok

  defp actor_matches(_, _), do: {:error, :actor_mismatch}

  defp referenced_activity_iri(%IRI{value: value}), do: {:ok, value}
  defp referenced_activity_iri(%Activity{id: %IRI{value: value}}), do: {:ok, value}
  defp referenced_activity_iri(_), do: {:error, :invalid_activity_reference}

  defp object_iri(%IRI{value: value}), do: value
  defp object_iri(%Activity{id: %IRI{value: value}}), do: value
  defp object_iri(_), do: nil

  defp activity_iri,
    do: IRI.parse!("#{Thicket.Federation.origin()}/ap/activities/#{Ecto.UUID.generate()}")

  defp now_iso8601, do: DateTime.utc_now(:second) |> DateTime.to_iso8601()
end
