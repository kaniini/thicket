defmodule Thicket.Federation.ParserTest do
  use ExUnit.Case, async: true

  alias Thicket.Federation.{Activity, Actor, IRI, Parser, Serializer}

  test "normalizes absolute HTTP IRIs" do
    assert {:ok, %IRI{value: "https://example.com/Users/A?x=1", host: "example.com"}} =
             IRI.parse("HTTPS://Example.COM:443/Users/A?x=1")

    assert {:error, :invalid_iri} = IRI.parse("acct:alice@example.com")
    assert {:error, :invalid_iri} = IRI.parse("https://alice:secret@example.com/")
  end

  test "normalizes actor documents into typed values" do
    document = %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "id" => "https://social.example/users/alice",
      "type" => "Person",
      "preferredUsername" => "alice",
      "inbox" => "https://social.example/users/alice/inbox",
      "endpoints" => %{"sharedInbox" => "https://social.example/inbox"},
      "publicKey" => %{
        "id" => "https://social.example/users/alice#main-key",
        "owner" => "https://social.example/users/alice",
        "publicKeyPem" => "-----BEGIN PUBLIC KEY-----\nkey\n-----END PUBLIC KEY-----"
      },
      "alsoKnownAs" => "https://example.net/@alice"
    }

    assert {:ok, %Actor{} = actor} = Parser.parse(document)
    assert actor.id.value == "https://social.example/users/alice"
    assert actor.shared_inbox.value == "https://social.example/inbox"
    assert actor.extensions["alsoKnownAs"] == "https://example.net/@alice"
    assert Serializer.to_map(actor)["preferredUsername"] == "alice"
  end

  test "normalizes singleton recipients and embedded objects" do
    document = %{
      "id" => "https://example.com/activities/1",
      "type" => "Create",
      "actor" => "https://example.com/users/alice",
      "to" => "https://www.w3.org/ns/activitystreams#Public",
      "object" => %{
        "id" => "https://example.com/posts/1",
        "type" => "Note",
        "content" => "<p>Hello</p>"
      }
    }

    assert {:ok, %Activity{} = activity} = Parser.parse(document)
    assert [public] = activity.recipients.to
    assert public.value == "https://www.w3.org/ns/activitystreams#Public"
    assert activity.object.content == "<p>Hello</p>"
  end

  test "rejects oversized, deeply nested, and unsafe documents without raising" do
    assert {:error, [%{code: :document_too_large}]} = Parser.decode("{}", max_bytes: 1)

    nested = Enum.reduce(1..40, %{"type" => "Note"}, fn _, acc -> %{"value" => acc} end)
    assert {:error, [%{code: :too_deep}]} = Parser.parse(nested)

    unsafe = %{
      "@context" => %{"actor" => "https://evil.example/actor"},
      "id" => "https://example.com/1",
      "type" => "Note"
    }

    assert {:error, [%{code: :unsafe_context}]} = Parser.parse(unsafe)
  end

  test "rejects unsupported types and mismatched key owners" do
    assert {:error, [%{code: :unsupported_type}]} =
             Parser.parse(%{"id" => "https://example.com/1", "type" => "Question"})

    actor = %{
      "id" => "https://example.com/alice",
      "type" => "Person",
      "publicKey" => %{
        "id" => "https://example.com/alice#main-key",
        "owner" => "https://evil.example/mallory",
        "publicKeyPem" => "key"
      }
    }

    assert {:error, [%{code: :owner_mismatch}]} = Parser.parse(actor)
  end
end
