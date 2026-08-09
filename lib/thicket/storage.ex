defmodule Thicket.Storage do
  @moduledoc "Storage boundary for local media."

  @callback put(Path.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  @callback url(String.t()) :: String.t()

  def adapter, do: Application.get_env(:thicket, :storage_adapter, Thicket.Storage.Local)

  def put(path, media_type) do
    with :ok <- Thicket.Media.validate_image(path, media_type),
         do: adapter().put(path, media_type)
  end

  def url(key), do: adapter().url(key)
end
