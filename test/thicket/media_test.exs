defmodule Thicket.MediaTest do
  use ExUnit.Case, async: true
  alias Thicket.Media

  test "accepts image signatures independently of filenames" do
    path = Path.join(System.tmp_dir!(), "thicket-media-#{System.unique_integer([:positive])}.bin")
    File.write!(path, <<0x89, "PNG\r\n", 0x1A, "\n", 0, 0, 0, 0>>)
    on_exit(fn -> File.rm(path) end)
    assert :ok = Media.validate_image(path, "image/png")
    assert {:error, :media_type_mismatch} = Media.validate_image(path, "image/jpeg")
  end
end
