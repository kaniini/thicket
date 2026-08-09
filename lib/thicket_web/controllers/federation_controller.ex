defmodule ThicketWeb.FederationController do
  use ThicketWeb, :controller

  alias Thicket.Federation
  alias Thicket.Federation.Serializer
  alias Thicket.Identity

  def webfinger(conn, %{"resource" => resource}) do
    with {:ok, handle} <- webfinger_handle(resource),
         channel when not is_nil(channel) <- Identity.get_channel_by_handle(handle) do
      actor = Federation.actor_iri(channel).value

      conn
      |> put_resp_content_type("application/jrd+json")
      |> json(%{
        "subject" => "acct:#{channel.handle}@#{Federation.authority()}",
        "aliases" => [actor],
        "links" => [
          %{
            "rel" => "self",
            "type" => "application/activity+json",
            "href" => actor
          }
        ]
      })
    else
      _ -> send_resp(conn, :not_found, "not found")
    end
  end

  def actor(conn, %{"handle" => handle}), do: with_channel(conn, handle, &Federation.actor/1)
  def outbox(conn, %{"handle" => handle}), do: with_channel(conn, handle, &Federation.outbox/1)

  def followers(conn, %{"handle" => handle}),
    do: with_channel(conn, handle, &Federation.followers/1)

  def following(conn, %{"handle" => handle}),
    do: with_channel(conn, handle, &Federation.following/1)

  def inbox(conn, params) do
    target = if handle = params["handle"], do: "channel:#{handle}", else: "shared"

    Thicket.Federation.Audit.record(%{
      direction: :inbound,
      category: "inbox",
      result: :rejected,
      request_id: List.first(get_req_header(conn, "x-request-id")),
      details: %{code: :follow_federation_not_enabled, object_type: target}
    })

    conn
    |> put_resp_content_type("application/activity+json")
    |> send_resp(
      :not_implemented,
      Jason.encode!(%{"error" => "federation delivery is not enabled yet"})
    )
  end

  def object(conn, %{"id" => id}) do
    case Federation.get_public_post(id) do
      nil -> send_resp(conn, :not_found, "not found")
      post -> activity_json(conn, Federation.project_post(post, post.channel))
    end
  end

  defp with_channel(conn, handle, projection) do
    case Identity.get_channel_by_handle(handle) do
      nil -> send_resp(conn, :not_found, "not found")
      channel -> activity_json(conn, projection.(channel))
    end
  end

  defp activity_json(conn, value) do
    conn
    |> put_resp_content_type("application/activity+json")
    |> send_resp(:ok, Serializer.encode!(value))
  end

  defp webfinger_handle("acct:" <> account) do
    case String.split(account, "@", parts: 2) do
      [handle, authority] when handle != "" ->
        if String.downcase(authority) == String.downcase(Federation.authority()),
          do: {:ok, handle},
          else: :error

      _ ->
        :error
    end
  end

  defp webfinger_handle(_), do: :error
end
