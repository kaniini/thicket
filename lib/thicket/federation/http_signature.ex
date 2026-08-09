defmodule Thicket.Federation.HTTPSignature do
  @moduledoc "Legacy HTTP Signature support used by Mastodon and Pleroma/Akkoma."

  alias Thicket.Federation.{IRI, KeyStore, SigningKey}

  @signed_headers ["(request-target)", "host", "date", "digest"]
  @max_clock_skew 300

  def sign(method, %IRI{} = iri, body, key_id, %SigningKey{} = key, now \\ DateTime.utc_now()) do
    with {:ok, private_key} <- KeyStore.private_key(key) do
      date = Req.Utils.format_http_date(now)
      digest = digest(body)
      headers = %{"host" => authority(iri), "date" => date, "digest" => digest}
      signing_string = signing_string(@signed_headers, method, request_target(iri), headers)
      signature = :public_key.sign(signing_string, :sha256, private_key) |> Base.encode64()

      {:ok,
       [
         {"host", headers["host"]},
         {"date", date},
         {"digest", digest},
         {"signature",
          ~s(keyId="#{key_id}",algorithm="rsa-sha256",headers="#{Enum.join(@signed_headers, " ")}",signature="#{signature}")}
       ]}
    end
  end

  def verify(method, request_target, headers, body, public_key_pem, now \\ DateTime.utc_now()) do
    headers = normalize_headers(headers)

    with {:ok, params} <- parse_signature(headers["signature"]),
         true <- params["algorithm"] in ["rsa-sha256", "hs2019"],
         signed_headers <- String.split(params["headers"] || "", " ", trim: true),
         true <- Enum.all?(@signed_headers, &(&1 in signed_headers)),
         true <- headers["digest"] == digest(body),
         {:ok, signed_at} <- Req.Utils.parse_http_date(headers["date"] || ""),
         true <- abs(DateTime.diff(now, signed_at, :second)) <= @max_clock_skew,
         {:ok, public_key} <- decode_public_key(public_key_pem),
         {:ok, signature} <- Base.decode64(params["signature"] || ""),
         signing_string <- signing_string(signed_headers, method, request_target, headers),
         true <- :public_key.verify(signing_string, :sha256, signature, public_key) do
      {:ok, params["keyId"]}
    else
      false -> {:error, :invalid_signature}
      {:error, _} = error -> error
      _ -> {:error, :invalid_signature}
    end
  end

  def digest(body), do: "SHA-256=" <> (:crypto.hash(:sha256, body || "") |> Base.encode64())

  defp signing_string(names, method, target, headers) do
    names
    |> Enum.map(fn
      "(request-target)" ->
        "(request-target): #{method |> to_string() |> String.downcase()} #{target}"

      name ->
        "#{name}: #{Map.fetch!(headers, name)}"
    end)
    |> Enum.join("\n")
  end

  defp parse_signature(nil), do: {:error, :missing_signature}

  defp parse_signature(header) when byte_size(header) <= 8_192 do
    params =
      Regex.scan(~r/(\w+)="([^"]*)"/, header)
      |> Enum.into(%{}, fn [_, key, value] -> {key, value} end)

    if Map.has_key?(params, "keyId") and Map.has_key?(params, "signature"),
      do: {:ok, params},
      else: {:error, :invalid_signature_header}
  end

  defp parse_signature(_), do: {:error, :invalid_signature_header}

  defp decode_public_key(pem) when is_binary(pem) do
    case :public_key.pem_decode(pem) do
      [entry] -> {:ok, :public_key.pem_entry_decode(entry)}
      _ -> {:error, :invalid_public_key}
    end
  rescue
    _ -> {:error, :invalid_public_key}
  end

  defp normalize_headers(headers) do
    Enum.into(headers, %{}, fn {key, value} ->
      value = if is_list(value), do: Enum.join(value, ", "), else: value
      {key |> to_string() |> String.downcase(), value}
    end)
  end

  defp authority(%IRI{scheme: scheme, host: host, port: port}) do
    if is_nil(port) or {scheme, port} in [{"http", 80}, {"https", 443}],
      do: host,
      else: "#{host}:#{port}"
  end

  defp request_target(%IRI{path: path, query: nil}), do: path
  defp request_target(%IRI{path: path, query: query}), do: "#{path}?#{query}"
end
