defmodule Thicket.Storage.S3 do
  @behaviour Thicket.Storage

  @extensions %{
    "image/avif" => ".avif",
    "image/gif" => ".gif",
    "image/jpeg" => ".jpg",
    "image/png" => ".png",
    "image/webp" => ".webp"
  }

  @impl true
  def put(source_path, media_type) do
    with extension when is_binary(extension) <- Map.get(@extensions, media_type),
         {:ok, body} <- File.read(source_path),
         key <- Ecto.UUID.generate() <> extension,
         {:ok, request} <- signed_request(key, media_type, body),
         {:ok, %{status: status}} when status in 200..299 <- Req.put(request) do
      {:ok, key}
    else
      nil -> {:error, :unsupported_media_type}
      {:ok, %{status: status, body: body}} -> {:error, {:s3_response, status, body}}
      error -> error
    end
  end

  @impl true
  def url(key) do
    base = config!(:public_base_url) |> String.trim_trailing("/")
    base <> "/" <> URI.encode(key)
  end

  defp signed_request(key, media_type, body) do
    endpoint = config!(:endpoint) |> String.trim_trailing("/")
    bucket = config!(:bucket)
    region = config!(:region)
    access_key_id = config!(:access_key_id)
    secret_access_key = config!(:secret_access_key)
    uri = URI.parse(endpoint)
    object_path = "/" <> Enum.map_join([bucket, key], "/", &URI.encode/1)
    url = endpoint <> object_path
    now = DateTime.utc_now()
    amz_date = Calendar.strftime(now, "%Y%m%dT%H%M%SZ")
    date = Calendar.strftime(now, "%Y%m%d")
    payload_hash = sha256_hex(body)
    host = uri.host <> if(uri.port && uri.port not in [80, 443], do: ":#{uri.port}", else: "")

    canonical_headers =
      "content-type:#{media_type}\nhost:#{host}\nx-amz-content-sha256:#{payload_hash}\nx-amz-date:#{amz_date}\n"

    signed_headers = "content-type;host;x-amz-content-sha256;x-amz-date"

    canonical_request =
      Enum.join(["PUT", object_path, "", canonical_headers, signed_headers, payload_hash], "\n")

    scope = "#{date}/#{region}/s3/aws4_request"

    string_to_sign =
      Enum.join(["AWS4-HMAC-SHA256", amz_date, scope, sha256_hex(canonical_request)], "\n")

    signature = signing_key(secret_access_key, date, region) |> hmac_hex(string_to_sign)

    authorization =
      "AWS4-HMAC-SHA256 Credential=#{access_key_id}/#{scope}, SignedHeaders=#{signed_headers}, Signature=#{signature}"

    {:ok,
     [
       url: url,
       body: body,
       headers: [
         {"authorization", authorization},
         {"content-type", media_type},
         {"host", host},
         {"x-amz-content-sha256", payload_hash},
         {"x-amz-date", amz_date}
       ]
     ]}
  end

  defp signing_key(secret, date, region) do
    ("AWS4" <> secret)
    |> hmac(date)
    |> hmac(region)
    |> hmac("s3")
    |> hmac("aws4_request")
  end

  defp hmac(key, value), do: :crypto.mac(:hmac, :sha256, key, value)
  defp hmac_hex(key, value), do: key |> hmac(value) |> Base.encode16(case: :lower)
  defp sha256_hex(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp config!(key), do: Application.fetch_env!(:thicket, __MODULE__) |> Keyword.fetch!(key)
end
