defmodule Thicket.Federation.Authenticator do
  @moduledoc "Authenticates inbox requests and performs one controlled key refresh on failure."

  alias Thicket.Federation.{HTTPSignature, IRI, RemoteActor, RemoteActors}

  def authenticate(method, request_target, headers, body, opts \\ []) do
    with {:ok, key_id} <- HTTPSignature.key_id(headers),
         {:ok, actor} <- actor_for_key(key_id, opts),
         :ok <- key_owned_by_actor(key_id, actor) do
      case verify(method, request_target, headers, body, actor) do
        {:ok, ^key_id} ->
          {:ok, actor}

        {:error, _} ->
          refresh_and_verify(method, request_target, headers, body, actor, key_id, opts)
      end
    end
  end

  defp actor_for_key(key_id, opts) do
    case RemoteActors.get_by_key_id(key_id) do
      %RemoteActor{} = actor ->
        {:ok, actor}

      nil ->
        with {:ok, actor_iri} <- actor_iri_from_key_id(key_id) do
          RemoteActors.get_or_fetch(actor_iri, opts)
        end
    end
  end

  defp refresh_and_verify(method, target, headers, body, actor, key_id, opts) do
    with {:ok, refreshed} <- RemoteActors.refresh(actor, opts),
         :ok <- key_owned_by_actor(key_id, refreshed),
         {:ok, ^key_id} <- verify(method, target, headers, body, refreshed) do
      {:ok, refreshed}
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp verify(method, target, headers, body, actor) do
    HTTPSignature.verify(method, target, headers, body, actor.public_key_pem)
  end

  defp key_owned_by_actor(key_id, %RemoteActor{public_key_id: key_id}), do: :ok
  defp key_owned_by_actor(_, _), do: {:error, :key_owner_mismatch}

  defp actor_iri_from_key_id(key_id) do
    with {:ok, iri} <- IRI.parse(key_id) do
      {:ok, URI.to_string(%URI{URI.parse(iri.value) | fragment: nil})}
    end
  end
end
