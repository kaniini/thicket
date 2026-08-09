defmodule Thicket.Federation.AuditTest do
  use Thicket.DataCase

  alias Thicket.Federation.Audit

  test "retains only bounded diagnostic metadata for administrators" do
    assert {:ok, _event} =
             Audit.record(%{
               direction: :inbound,
               category: "signature",
               result: :rejected,
               domain: "remote.example",
               details: %{code: :invalid_signature, authorization: "secret", status: 401}
             })

    assert [event] = Audit.list_recent(%Thicket.Identity.User{admin: true})
    assert event.details == %{"code" => "invalid_signature", "status" => 401}
    assert {:error, :unauthorized} = Audit.list_recent(%Thicket.Identity.User{admin: false})
  end
end
