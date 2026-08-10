defmodule Thicket.Federation.TestDeliveryTransport do
  @behaviour Thicket.Federation.DeliveryTransport

  @impl true
  def post(url, headers, body) do
    if pid = Application.get_env(:thicket, :delivery_test_pid) do
      send(pid, {:federation_delivery, url, headers, body})
    end

    Application.get_env(:thicket, :delivery_test_result, {:ok, 202})
  end
end
