defmodule Thicket.Federation.HTTPSignatureTest do
  use Thicket.DataCase

  import Thicket.IdentityFixtures

  alias Thicket.Federation.{HTTPSignature, IRI, KeyStore}

  test "signs and verifies a request and rejects tampering and stale dates" do
    {:ok, user} = Thicket.Identity.register_invited_user(valid_registration_attributes())
    channel = user |> Thicket.Identity.list_channels() |> hd()
    {:ok, key} = KeyStore.ensure_key(channel)
    iri = IRI.parse!("https://remote.example/inbox?shared=true")
    now = ~U[2026-08-09 12:00:00Z]

    assert {:ok, signed_headers} =
             HTTPSignature.sign(
               :post,
               iri,
               ~s({"hello":"world"}),
               "https://local.example/key",
               key,
               now
             )

    assert {:ok, "https://local.example/key"} =
             HTTPSignature.verify(
               :post,
               "/inbox?shared=true",
               signed_headers,
               ~s({"hello":"world"}),
               key.public_key_pem,
               now
             )

    assert {:error, :invalid_signature} =
             HTTPSignature.verify(
               :post,
               "/inbox?shared=true",
               signed_headers,
               "tampered",
               key.public_key_pem,
               now
             )

    assert {:error, :invalid_signature} =
             HTTPSignature.verify(
               :post,
               "/inbox?shared=true",
               signed_headers,
               ~s({"hello":"world"}),
               key.public_key_pem,
               DateTime.add(now, 301)
             )
  end
end
