defmodule Thicket.Federation.IRI do
  @moduledoc "A normalized absolute HTTP(S) IRI used at the federation boundary."

  @enforce_keys [:value, :scheme, :host]
  defstruct [:value, :scheme, :host, :port, :path, :query, :fragment]

  @type t :: %__MODULE__{
          value: String.t(),
          scheme: String.t(),
          host: String.t(),
          port: non_neg_integer() | nil,
          path: String.t(),
          query: String.t() | nil,
          fragment: String.t() | nil
        }

  @spec parse(term()) :: {:ok, t()} | {:error, :invalid_iri}
  def parse(value) when is_binary(value) and byte_size(value) <= 8_192 do
    with %URI{scheme: scheme, host: host, userinfo: nil} = uri <- URI.parse(value),
         true <- scheme in ["http", "https"],
         true <- is_binary(host) and host != "",
         true <- valid_port?(uri.port) do
      scheme = String.downcase(scheme)
      host = String.downcase(host)
      port = normalize_port(scheme, uri.port)
      path = if uri.path in [nil, ""], do: "/", else: uri.path
      normalized = %URI{uri | scheme: scheme, host: host, port: port, path: path}

      {:ok,
       %__MODULE__{
         value: URI.to_string(normalized),
         scheme: scheme,
         host: host,
         port: port,
         path: path,
         query: uri.query,
         fragment: uri.fragment
       }}
    else
      _ -> {:error, :invalid_iri}
    end
  end

  def parse(_value), do: {:error, :invalid_iri}

  def parse!(value) do
    case parse(value) do
      {:ok, iri} -> iri
      {:error, reason} -> raise ArgumentError, "invalid federation IRI: #{inspect(reason)}"
    end
  end

  defp valid_port?(nil), do: true
  defp valid_port?(port), do: is_integer(port) and port in 1..65_535

  defp normalize_port("http", 80), do: nil
  defp normalize_port("https", 443), do: nil
  defp normalize_port(_scheme, port), do: port
end
