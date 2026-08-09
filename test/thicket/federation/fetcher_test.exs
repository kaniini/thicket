defmodule Thicket.Federation.FetcherTest do
  use Thicket.DataCase

  alias Thicket.Federation.{Actor, Audit, Fetcher}

  test "fetches and parses a bounded ActivityStreams document" do
    request = fn url, headers, _opts ->
      assert url == "https://social.example/users/alice"
      assert {"accept", _} = List.keyfind(headers, "accept", 0)

      {:ok,
       %{
         status: 200,
         headers: %{"content-type" => ["application/activity+json"]},
         body: Jason.encode!(%{"id" => url, "type" => "Person", "preferredUsername" => "alice"})
       }}
    end

    assert {:ok, %Actor{preferred_username: "alice"}} =
             Fetcher.fetch("https://social.example/users/alice",
               resolver: &public_resolver/1,
               request_fun: request
             )
  end

  test "rejects local addresses, plain HTTP, hostile redirects, types, and oversized bodies" do
    request = fn _url, _headers, _opts ->
      {:ok, %{status: 200, headers: %{"content-type" => ["text/html"]}, body: "<html>"}}
    end

    assert {:error, :private_address} = Fetcher.fetch("https://127.0.0.1/actor")
    assert {:error, :https_required} = Fetcher.fetch("http://social.example/actor")

    assert {:error, :unsupported_content_type} =
             Fetcher.fetch("https://social.example/actor",
               resolver: &public_resolver/1,
               request_fun: request
             )

    redirect = fn _url, _headers, _opts ->
      {:ok, %{status: 302, headers: %{"location" => ["https://127.0.0.1/private"]}, body: ""}}
    end

    assert {:error, :unsafe_redirect} =
             Fetcher.fetch("https://social.example/actor",
               resolver: &public_resolver/1,
               request_fun: redirect
             )

    large = fn _url, _headers, _opts ->
      {:ok,
       %{
         status: 200,
         headers: %{"content-type" => ["application/activity+json"]},
         body: String.duplicate("x", 20)
       }}
    end

    assert {:error, :document_too_large} =
             Fetcher.fetch("https://social.example/actor",
               resolver: &public_resolver/1,
               request_fun: large,
               max_bytes: 10
             )
  end

  test "records sanitized operator diagnostics" do
    assert {:error, :https_required} = Fetcher.fetch("http://social.example/actor")
    admin = %Thicket.Identity.User{admin: true}
    assert [event | _] = Audit.list_recent(admin)
    assert event.category == "fetch"
    assert event.domain == "social.example"
    assert event.details["code"] == "https_required"
    refute Map.has_key?(event.details, "authorization")
  end

  defp public_resolver("127.0.0.1"), do: {:ok, [{127, 0, 0, 1}]}
  defp public_resolver(_host), do: {:ok, [{93, 184, 216, 34}]}
end
