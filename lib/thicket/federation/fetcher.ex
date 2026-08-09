defmodule Thicket.Federation.Fetcher do
  @moduledoc "Authenticated remote document fetches with SSRF and response bounds."

  alias Thicket.Federation.{Audit, HTTPSignature, IRI, KeyStore, Parser}
  alias Thicket.Identity.Channel

  @redirect_statuses [301, 302, 303, 307, 308]
  @accepted_types ["application/activity+json", "application/ld+json", "application/json"]

  def fetch(url, opts \\ []) do
    started = System.monotonic_time(:millisecond)

    result =
      with {:ok, iri} <- IRI.parse(url),
           :ok <- safe_destination(iri, opts),
           {:ok, response} <- request(iri, opts, 0),
           :ok <- accepted_response(response, opts),
           {:ok, value} <- Parser.decode(response.body, parser_options(opts)) do
        {:ok, value}
      end

    audit_fetch(url, result, System.monotonic_time(:millisecond) - started)
    result
  end

  defp request(iri, opts, redirects) when redirects <= 3 do
    headers = [{"accept", "application/activity+json, application/ld+json"}]

    with {:ok, headers} <- maybe_sign(headers, iri, Keyword.get(opts, :channel)),
         {:ok, response} <- request_fun(opts).(iri.value, headers, opts) do
      if response.status in @redirect_statuses do
        with [location | _] <- response_header(response, "location"),
             {:ok, redirected} <- resolve_redirect(iri, location),
             :ok <- safe_destination(redirected, opts) do
          request(redirected, opts, redirects + 1)
        else
          _ -> {:error, :unsafe_redirect}
        end
      else
        {:ok, response}
      end
    end
  end

  defp request(_iri, _opts, _redirects), do: {:error, :too_many_redirects}

  defp default_request(url, headers, opts) do
    request_opts = [
      url: url,
      method: :get,
      headers: headers,
      redirect: false,
      retry: false,
      receive_timeout: Keyword.get(opts, :receive_timeout, 10_000),
      connect_options: [timeout: Keyword.get(opts, :connect_timeout, 5_000)],
      decode_body: false
    ]

    case Req.request(request_opts) do
      {:ok, response} -> {:ok, response}
      {:error, exception} -> {:error, {:network, Exception.message(exception)}}
    end
  end

  defp maybe_sign(headers, _iri, nil), do: {:ok, headers}

  defp maybe_sign(headers, iri, %Channel{} = channel) do
    with {:ok, key} <- KeyStore.ensure_key(channel),
         {:ok, signed} <-
           HTTPSignature.sign(
             :get,
             iri,
             "",
             "#{Thicket.Federation.actor_iri(channel).value}#main-key",
             key
           ) do
      {:ok, headers ++ signed}
    end
  end

  defp safe_destination(%IRI{scheme: "http"} = iri, opts) do
    if Keyword.get(opts, :allow_http, false),
      do: resolve_public(iri, opts),
      else: {:error, :https_required}
  end

  defp safe_destination(%IRI{} = iri, opts), do: resolve_public(iri, opts)

  defp resolve_public(%IRI{host: host}, opts) do
    resolver = Keyword.get(opts, :resolver, &:inet.getaddrs(String.to_charlist(&1), :inet))

    case resolver.(host) do
      {:ok, addresses} when addresses != [] ->
        if Enum.all?(addresses, &public_address?/1), do: :ok, else: {:error, :private_address}

      _ ->
        {:error, :dns_failure}
    end
  end

  defp public_address?({a, b, _c, _d}) do
    not (a in [0, 10, 127] or a >= 224 or {a, b} in [{169, 254}, {192, 168}] or
           (a == 172 and b in 16..31))
  end

  defp public_address?({0, 0, 0, 0, 0, 0, 0, 1}), do: false
  defp public_address?({0, 0, 0, 0, 0, 0xFFFF, _, _}), do: false

  defp public_address?({first, _, _, _, _, _, _, _}),
    do: Bitwise.band(first, 0xFE00) != 0xFC00 and Bitwise.band(first, 0xFFC0) != 0xFE80

  defp public_address?(_), do: false

  defp accepted_response(%{status: status}, _opts) when status < 200 or status >= 300,
    do: {:error, {:http_status, status}}

  defp accepted_response(response, opts) do
    max_bytes = Keyword.get(opts, :max_bytes, federation_config(:max_document_bytes))
    content_type = response_header(response, "content-type") |> List.first() |> media_type()

    cond do
      not is_binary(response.body) -> {:error, :invalid_body}
      byte_size(response.body) > max_bytes -> {:error, :document_too_large}
      content_type not in @accepted_types -> {:error, :unsupported_content_type}
      true -> :ok
    end
  end

  defp response_header(%{headers: headers}, name) when is_map(headers),
    do: Map.get(headers, name, [])

  defp response_header(%{headers: headers}, name) when is_list(headers),
    do: for({key, value} <- headers, String.downcase(key) == name, do: value)

  defp media_type(nil), do: nil

  defp media_type(value),
    do: value |> String.split(";", parts: 2) |> hd() |> String.downcase() |> String.trim()

  defp resolve_redirect(base, location) do
    base.value |> URI.merge(location) |> URI.to_string() |> IRI.parse()
  rescue
    _ -> {:error, :invalid_redirect}
  end

  defp request_fun(opts), do: Keyword.get(opts, :request_fun, &default_request/3)

  defp parser_options(opts),
    do: [max_bytes: Keyword.get(opts, :max_bytes, federation_config(:max_document_bytes))]

  defp federation_config(key),
    do: :thicket |> Application.fetch_env!(:federation) |> Keyword.fetch!(key)

  defp audit_fetch(url, result, elapsed_ms) do
    iri =
      case IRI.parse(url) do
        {:ok, parsed} -> parsed
        _ -> nil
      end

    {audit_result, code} =
      case result do
        {:ok, _} -> {:accepted, :ok}
        {:error, reason} -> {:failed, reason}
      end

    Audit.record(%{
      direction: :outbound,
      category: "fetch",
      result: audit_result,
      iri: if(iri, do: iri.value),
      domain: if(iri, do: iri.host),
      details: %{code: code, elapsed_ms: elapsed_ms}
    })
  end
end
