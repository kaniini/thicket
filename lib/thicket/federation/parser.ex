defmodule Thicket.Federation.Parser do
  @moduledoc "Bounded, non-raising parsing into Thicket's supported ActivityStreams profile."

  alias Thicket.Federation.{
    Activity,
    Actor,
    Collection,
    Error,
    IRI,
    Object,
    PublicKey,
    Recipients
  }

  @activity_types ~w(Create Update Delete Follow Accept Reject Undo Like Announce)
  @actor_types ~w(Person Application Service)
  @object_types ~w(Note Article)
  @collection_types ~w(Collection OrderedCollection CollectionPage OrderedCollectionPage)
  @contexts [
    "https://www.w3.org/ns/activitystreams",
    "https://w3id.org/security/v1",
    "https://w3id.org/security/v2"
  ]
  @max_bytes 1_048_576
  @max_depth 32
  @max_nodes 20_000

  @spec decode(binary(), keyword()) :: {:ok, struct()} | {:error, [Error.t()]}
  def decode(json, opts \\ [])

  def decode(json, opts) when is_binary(json) do
    max_bytes = Keyword.get(opts, :max_bytes, @max_bytes)

    if byte_size(json) > max_bytes do
      error(:document_too_large, [], "document exceeds #{max_bytes} bytes")
    else
      case Jason.decode(json, strings: :copy) do
        {:ok, value} -> parse(value, opts)
        {:error, _} -> error(:invalid_json, [], "document is not valid JSON")
      end
    end
  end

  def decode(_json, _opts), do: error(:invalid_json, [], "document must be JSON bytes")

  @spec parse(term(), keyword()) :: {:ok, struct()} | {:error, [Error.t()]}
  def parse(value, opts \\ []) do
    with :ok <- bounded?(value, Keyword.get(opts, :max_depth, @max_depth), @max_nodes),
         :ok <- context_valid?(value),
         {:ok, type} <- required_string(value, "type", []),
         {:ok, parsed} <- parse_type(type, value) do
      {:ok, parsed}
    else
      {:error, %Error{} = issue} -> {:error, [issue]}
      {:error, issues} when is_list(issues) -> {:error, issues}
    end
  end

  defp parse_type(type, value) when type in @activity_types, do: parse_activity(type, value)
  defp parse_type(type, value) when type in @actor_types, do: parse_actor(type, value)
  defp parse_type(type, value) when type in @object_types, do: parse_object(type, value)
  defp parse_type(type, value) when type in @collection_types, do: parse_collection(type, value)

  defp parse_type(type, _value),
    do: issue(:unsupported_type, ["type"], "unsupported ActivityStreams type #{inspect(type)}")

  defp parse_activity(type, value) do
    with {:ok, id} <- required_iri(value, "id"),
         {:ok, actor} <- required_iri(value, "actor"),
         {:ok, object} <- activity_object(Map.get(value, "object")),
         {:ok, recipients} <- recipients(value) do
      {:ok,
       %Activity{
         id: id,
         type: type,
         actor: actor,
         object: object,
         published: optional_string(value, "published"),
         recipients: recipients,
         extensions:
           extensions(value, ~w(@context id type actor object published to cc bto bcc audience))
       }}
    end
  end

  defp parse_actor(type, value) do
    with {:ok, id} <- required_iri(value, "id"),
         {:ok, inbox} <- optional_iri(value, "inbox"),
         {:ok, outbox} <- optional_iri(value, "outbox"),
         {:ok, followers} <- optional_iri(value, "followers"),
         {:ok, following} <- optional_iri(value, "following"),
         {:ok, shared_inbox} <- shared_inbox(value),
         {:ok, public_key} <- public_key(Map.get(value, "publicKey"), id) do
      {:ok,
       %Actor{
         id: id,
         type: type,
         preferred_username: optional_string(value, "preferredUsername"),
         name: optional_string(value, "name"),
         summary: optional_string(value, "summary"),
         inbox: inbox,
         outbox: outbox,
         followers: followers,
         following: following,
         shared_inbox: shared_inbox,
         public_key: public_key,
         extensions:
           extensions(
             value,
             ~w(@context id type preferredUsername name summary inbox outbox followers following endpoints publicKey icon image)
           )
       }}
    end
  end

  defp parse_object(type, value) do
    with {:ok, id} <- required_iri(value, "id"),
         {:ok, attributed_to} <- optional_iri(value, "attributedTo"),
         {:ok, in_reply_to} <- optional_iri(value, "inReplyTo"),
         {:ok, recipients} <- recipients(value) do
      {:ok,
       %Object{
         id: id,
         type: type,
         attributed_to: attributed_to,
         name: optional_string(value, "name"),
         summary: optional_string(value, "summary"),
         content: optional_string(value, "content"),
         media_type: optional_string(value, "mediaType"),
         source: source(Map.get(value, "source")),
         in_reply_to: in_reply_to,
         published: optional_string(value, "published"),
         updated: optional_string(value, "updated"),
         recipients: recipients,
         extensions:
           extensions(
             value,
             ~w(@context id type attributedTo name summary content mediaType source inReplyTo published updated to cc bto bcc audience attachment tag)
           )
       }}
    end
  end

  defp parse_collection(type, value) do
    with {:ok, id} <- required_iri(value, "id"),
         {:ok, first} <- optional_iri(value, "first"),
         {:ok, next} <- optional_iri(value, "next"),
         {:ok, prev} <- optional_iri(value, "prev") do
      {:ok,
       %Collection{
         id: id,
         type: type,
         total_items: optional_non_negative_integer(value, "totalItems"),
         first: first,
         next: next,
         prev: prev,
         ordered_items: list(Map.get(value, "orderedItems")),
         items: list(Map.get(value, "items"))
       }}
    end
  end

  defp activity_object(nil), do: {:ok, nil}
  defp activity_object(value) when is_binary(value), do: parse_iri(value, ["object"])
  defp activity_object(%{} = value), do: parse(value)
  defp activity_object(_), do: issue(:invalid_value, ["object"], "must be an IRI or object")

  defp public_key(nil, _actor_id), do: {:ok, nil}

  defp public_key(%{} = value, actor_id) do
    with {:ok, id} <- required_iri(value, "id", ["publicKey"]),
         {:ok, owner} <- required_iri(value, "owner", ["publicKey"]),
         true <- owner.value == actor_id.value,
         {:ok, pem} <- required_string(value, "publicKeyPem", ["publicKey"]) do
      {:ok, %PublicKey{id: id, owner: owner, public_key_pem: pem}}
    else
      false ->
        issue(:owner_mismatch, ["publicKey", "owner"], "public key owner must match actor id")

      other ->
        other
    end
  end

  defp public_key(_, _), do: issue(:invalid_value, ["publicKey"], "must be an object")

  defp shared_inbox(%{"endpoints" => %{"sharedInbox" => value}}),
    do: parse_iri(value, ["endpoints", "sharedInbox"])

  defp shared_inbox(_), do: {:ok, nil}

  defp recipients(value) do
    Enum.reduce_while(~w(to cc bto bcc audience), {:ok, %Recipients{}}, fn key, {:ok, acc} ->
      case iri_list(Map.get(value, key), [key]) do
        {:ok, iris} -> {:cont, {:ok, Map.put(acc, String.to_existing_atom(key), iris)}}
        error -> {:halt, error}
      end
    end)
  end

  defp iri_list(nil, _path), do: {:ok, []}

  defp iri_list(value, path) do
    value
    |> list()
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, acc} ->
      case parse_iri(item, path ++ [index]) do
        {:ok, iri} -> {:cont, {:ok, acc ++ [iri]}}
        error -> {:halt, error}
      end
    end)
  end

  defp required_iri(value, key, prefix \\ []) do
    case Map.fetch(value, key) do
      {:ok, iri} -> parse_iri(iri, prefix ++ [key])
      :error -> issue(:required, prefix ++ [key], "is required")
    end
  end

  defp optional_iri(value, key) do
    case Map.get(value, key) do
      nil -> {:ok, nil}
      iri -> parse_iri(iri, [key])
    end
  end

  defp parse_iri(value, path) do
    case IRI.parse(value) do
      {:ok, iri} -> {:ok, iri}
      {:error, _} -> issue(:invalid_iri, path, "must be an absolute HTTP(S) IRI")
    end
  end

  defp required_string(value, key, prefix) do
    case Map.get(value, key) do
      string when is_binary(string) and string != "" -> {:ok, string}
      _ -> issue(:required, prefix ++ [key], "must be a non-empty string")
    end
  end

  defp optional_string(value, key) do
    case Map.get(value, key) do
      string when is_binary(string) -> string
      _ -> nil
    end
  end

  defp optional_non_negative_integer(value, key) do
    case Map.get(value, key) do
      integer when is_integer(integer) and integer >= 0 -> integer
      _ -> nil
    end
  end

  defp source(%{"content" => content, "mediaType" => media_type})
       when is_binary(content) and is_binary(media_type),
       do: %{content: content, media_type: media_type}

  defp source(_), do: nil
  defp list(nil), do: []
  defp list(value) when is_list(value), do: value
  defp list(value), do: [value]

  defp context_valid?(%{"@context" => context}) do
    context
    |> list()
    |> Enum.reduce_while(:ok, fn context, :ok ->
      case context do
        context when context in @contexts ->
          {:cont, :ok}

        %{} = context ->
          case validate_context_map(context) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end

        _ ->
          {:halt, issue(:unknown_context, ["@context"], "contains an unsupported context")}
      end
    end)
  end

  defp context_valid?(%{}), do: :ok
  defp context_valid?(_), do: issue(:invalid_document, [], "document must be an object")

  defp validate_context_map(context) do
    sensitive = ~w(id type actor object inbox owner publicKey publicKeyPem)

    if Enum.any?(sensitive, &Map.has_key?(context, &1)) do
      issue(:unsafe_context, ["@context"], "redefines a security-sensitive term")
    else
      :ok
    end
  end

  defp bounded?(value, max_depth, max_nodes) do
    case count_nodes(value, 0, max_depth, 0, max_nodes) do
      {:ok, _} -> :ok
      {:error, :depth} -> issue(:too_deep, [], "document exceeds nesting limit")
      {:error, :nodes} -> issue(:too_complex, [], "document exceeds structural complexity limit")
    end
  end

  defp count_nodes(_value, depth, max_depth, _count, _max) when depth > max_depth,
    do: {:error, :depth}

  defp count_nodes(_value, _depth, _max_depth, count, max) when count >= max,
    do: {:error, :nodes}

  defp count_nodes(%{} = value, depth, max_depth, count, max) do
    Enum.reduce_while(value, {:ok, count + 1}, fn {_key, child}, {:ok, acc} ->
      case count_nodes(child, depth + 1, max_depth, acc, max) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
  end

  defp count_nodes(value, depth, max_depth, count, max) when is_list(value) do
    Enum.reduce_while(value, {:ok, count + 1}, fn child, {:ok, acc} ->
      case count_nodes(child, depth + 1, max_depth, acc, max) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
  end

  defp count_nodes(_value, _depth, _max_depth, count, _max), do: {:ok, count + 1}

  defp extensions(value, known), do: Map.drop(value, known)
  defp issue(code, path, message), do: {:error, %Error{code: code, path: path, message: message}}

  defp error(code, path, message),
    do: {:error, [%Error{code: code, path: path, message: message}]}
end
