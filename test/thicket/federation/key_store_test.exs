defmodule Thicket.Federation.KeyStoreTest do
  use Thicket.DataCase

  import Thicket.IdentityFixtures

  alias Thicket.Federation.KeyStore

  test "stores channel private keys encrypted and decrypts them for signing" do
    {:ok, user} = Thicket.Identity.register_invited_user(valid_registration_attributes())
    channel = user |> Thicket.Identity.list_channels() |> hd()

    assert {:ok, key} = KeyStore.ensure_key(channel)
    refute key.encrypted_private_key =~ "BEGIN"
    assert key.public_key_pem =~ "BEGIN PUBLIC KEY"
    assert {:ok, {:RSAPrivateKey, _, _, _, _, _, _, _, _, _, _}} = KeyStore.private_key(key)

    assert {:ok, same_key} = KeyStore.ensure_key(channel)
    assert same_key.id == key.id
  end
end
