defmodule Thicket.Storage.Local do
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
         key <- Ecto.UUID.generate() <> extension,
         root <- Application.get_env(:thicket, :uploads_root, default_root()),
         :ok <- File.mkdir_p(root),
         {:ok, _bytes} <- File.copy(source_path, Path.join(root, key)) do
      {:ok, key}
    else
      nil -> {:error, :unsupported_media_type}
      error -> error
    end
  end

  @impl true
  def url(key), do: "/uploads/" <> key

  defp default_root, do: Application.app_dir(:thicket, "priv/static/uploads")
end
