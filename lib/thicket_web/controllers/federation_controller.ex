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
    case params do
      %{"handle" => handle} -> channel_inbox(conn, handle)
      _ -> federation_error(conn, :not_implemented, :shared_inbox_not_enabled)
    end
  end

  defp channel_inbox(conn, handle) do
    with channel when not is_nil(channel) <- Identity.get_channel_by_handle(handle),
         {:ok, body, conn} <- read_bounded_body(conn),
         {:ok, actor} <-
           Thicket.Federation.Authenticator.authenticate(
             conn.method,
             conn.request_path <> query_suffix(conn),
             request_headers(conn),
             body
           ),
         false <- Thicket.Moderation.domain_suspended?(actor.source_authority),
         {:ok, %Thicket.Federation.Activity{} = activity} <-
           Thicket.Federation.Parser.decode(body),
         {:ok, result} <- Thicket.Federation.Inbox.process(activity, actor, channel, body) do
      case result do
        {:rejected, _receipt, reason} -> federation_error(conn, :unprocessable_entity, reason)
        _ -> send_resp(conn, :accepted, "")
      end
    else
      nil ->
        federation_error(conn, :not_found, :unknown_channel)

      true ->
        federation_error(conn, :forbidden, :domain_suspended)

      {:more, _partial, conn} ->
        federation_error(conn, :request_entity_too_large, :body_too_large)

      {:error, :activity_id_collision} ->
        federation_error(conn, :conflict, :activity_id_collision)

      {:error, errors} when is_list(errors) ->
        federation_error(conn, :bad_request, :invalid_activity)

      {:error, reason} ->
        federation_error(conn, :unauthorized, reason)
    end
  end

  defp read_bounded_body(conn) do
    max = :thicket |> Application.fetch_env!(:federation) |> Keyword.fetch!(:max_document_bytes)

    case conn.private[:thicket_raw_body] do
      body when is_binary(body) and byte_size(body) <= max -> {:ok, body, conn}
      body when is_binary(body) -> {:more, body, conn}
      nil -> Plug.Conn.read_body(conn, length: max, read_length: min(max, 64_000))
    end
  end

  defp query_suffix(%{query_string: ""}), do: ""
  defp query_suffix(%{query_string: query}), do: "?#{query}"

  defp request_headers(conn) do
    default_port =
      (conn.scheme == :http and conn.port == 80) or (conn.scheme == :https and conn.port == 443)

    host = if default_port, do: conn.host, else: "#{conn.host}:#{conn.port}"

    [
      {"host", host}
      | Enum.reject(conn.req_headers, fn {name, _value} -> String.downcase(name) == "host" end)
    ]
  end

  defp federation_error(conn, status, reason) do
    Thicket.Federation.Audit.record(%{
      direction: :inbound,
      category: "inbox",
      result: :rejected,
      request_id: List.first(get_req_header(conn, "x-request-id")),
      details: %{code: reason, status: Plug.Conn.Status.code(status)}
    })

    conn
    |> put_resp_content_type("application/activity+json")
    |> send_resp(status, Jason.encode!(%{"error" => to_string(reason)}))
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
