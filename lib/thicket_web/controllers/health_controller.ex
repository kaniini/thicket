defmodule ThicketWeb.HealthController do
  use ThicketWeb, :controller

  def live(conn, _params), do: json(conn, %{status: "ok"})

  def ready(conn, _params) do
    case Ecto.Adapters.SQL.query(Thicket.Repo, "SELECT 1", []) do
      {:ok, _} ->
        json(conn, %{status: "ready", database: "ok"})

      {:error, _} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "unavailable", database: "error"})
    end
  end
end
