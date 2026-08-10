defmodule Thicket.Federation.ReqDeliveryTransport do
  @behaviour Thicket.Federation.DeliveryTransport

  alias Thicket.Federation.Fetcher

  @impl true
  def post(url, headers, body) do
    with :ok <- Fetcher.validate_destination(url),
         {:ok, response} <-
           Req.post(url,
             headers: [
               {"content-type", "application/activity+json"},
               {"accept", "application/activity+json"} | headers
             ],
             body: body,
             redirect: false,
             retry: false,
             receive_timeout: 10_000,
             connect_options: [timeout: 5_000],
             decode_body: false
           ) do
      {:ok, response.status}
    else
      {:error, exception} when is_exception(exception) -> {:error, Exception.message(exception)}
      {:error, reason} -> {:error, reason}
    end
  end
end
