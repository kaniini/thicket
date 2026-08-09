defmodule Thicket.Media do
  @moduledoc "Content-based validation for locally uploaded media."

  @max_image_bytes 20_000_000

  def validate_image(path, media_type) do
    with {:ok, %{size: size}} when size in 1..@max_image_bytes <- File.stat(path),
         {:ok, bytes} when is_binary(bytes) <-
           File.open(path, [:read, :binary], fn file -> IO.binread(file, 32) end) do
      if signature?(bytes, media_type), do: :ok, else: {:error, :media_type_mismatch}
    else
      {:ok, %{size: _size}} -> {:error, :invalid_media_size}
      {:ok, :eof} -> {:error, :empty_media}
      :eof -> {:error, :empty_media}
      error -> error
    end
  end

  defp signature?(<<0xFF, 0xD8, 0xFF, _::binary>>, "image/jpeg"), do: true
  defp signature?(<<0x89, "PNG\r\n", 0x1A, "\n", _::binary>>, "image/png"), do: true
  defp signature?(<<"GIF87a", _::binary>>, "image/gif"), do: true
  defp signature?(<<"GIF89a", _::binary>>, "image/gif"), do: true
  defp signature?(<<"RIFF", _size::binary-size(4), "WEBP", _::binary>>, "image/webp"), do: true

  defp signature?(
         <<_size::binary-size(4), "ftyp", brand::binary-size(4), _::binary>>,
         "image/avif"
       )
       when brand in ["avif", "avis"],
       do: true

  defp signature?(_bytes, _media_type), do: false
end
