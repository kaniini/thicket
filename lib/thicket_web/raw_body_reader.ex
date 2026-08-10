defmodule ThicketWeb.RawBodyReader do
  @moduledoc false

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} -> {:ok, body, cache(conn, body)}
      {:more, body, conn} -> {:more, body, cache(conn, body)}
      other -> other
    end
  end

  defp cache(conn, body) do
    Plug.Conn.put_private(
      conn,
      :thicket_raw_body,
      (conn.private[:thicket_raw_body] || "") <> body
    )
  end
end
