defmodule Thicket.Federation.KeyStore do
  @moduledoc "Generates and encrypts channel RSA signing keys."

  alias Thicket.Federation.SigningKey
  alias Thicket.Identity.Channel
  alias Thicket.Repo

  @aad "thicket:federation-key:v1"

  def ensure_key(%Channel{id: channel_id}) do
    case Repo.get_by(SigningKey, channel_id: channel_id) do
      nil -> create_key(channel_id)
      key -> {:ok, key}
    end
  end

  def private_key(%SigningKey{encrypted_private_key: encrypted}) do
    with <<nonce::binary-size(12), tag::binary-size(16), ciphertext::binary>> <- encrypted,
         plaintext when is_binary(plaintext) <-
           :crypto.crypto_one_time_aead(
             :aes_256_gcm,
             encryption_key(),
             nonce,
             ciphertext,
             @aad,
             tag,
             false
           ),
         [entry] <- :public_key.pem_decode(plaintext) do
      {:ok, :public_key.pem_entry_decode(entry)}
    else
      _ -> {:error, :invalid_private_key}
    end
  end

  defp create_key(channel_id) do
    private_key = :public_key.generate_key({:rsa, 2048, 65_537})
    {:RSAPrivateKey, _, modulus, exponent, _, _, _, _, _, _, _} = private_key
    public_key = {:RSAPublicKey, modulus, exponent}

    private_pem = :public_key.pem_entry_encode(:RSAPrivateKey, private_key) |> pem()
    public_pem = :public_key.pem_entry_encode(:SubjectPublicKeyInfo, public_key) |> pem()
    fingerprint = :crypto.hash(:sha256, public_pem) |> Base.encode16(case: :lower)

    %SigningKey{channel_id: channel_id}
    |> SigningKey.changeset(%{
      public_key_pem: public_pem,
      encrypted_private_key: encrypt(private_pem),
      fingerprint: fingerprint
    })
    |> Repo.insert(on_conflict: :nothing, conflict_target: :channel_id)
    |> case do
      {:ok, %SigningKey{id: nil}} -> {:ok, Repo.get_by!(SigningKey, channel_id: channel_id)}
      result -> result
    end
  end

  defp encrypt(plaintext) do
    nonce = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(
        :aes_256_gcm,
        encryption_key(),
        nonce,
        plaintext,
        @aad,
        true
      )

    nonce <> tag <> ciphertext
  end

  defp encryption_key do
    :thicket
    |> Application.fetch_env!(:federation)
    |> Keyword.fetch!(:key_base)
    |> then(&:crypto.hash(:sha256, &1))
  end

  defp pem(entry), do: :public_key.pem_encode([entry])
end
