defmodule Thicket.Federation.Audit do
  @moduledoc "Privacy-conscious federation diagnostics. Raw documents and credentials are never stored."

  import Ecto.Query

  alias Thicket.Federation.AuditEvent
  alias Thicket.Identity.User
  alias Thicket.Repo

  @allowed_detail_keys ~w(code status activity_type object_type elapsed_ms)a

  def record(attrs) when is_map(attrs) do
    attrs = Map.update(attrs, :details, %{}, &sanitize_details/1)
    %AuditEvent{} |> AuditEvent.changeset(attrs) |> Repo.insert()
  end

  def list_recent(user, limit \\ 100)

  def list_recent(%User{admin: true}, limit) do
    AuditEvent
    |> order_by([event], desc: event.inserted_at)
    |> limit(^min(limit, 500))
    |> Repo.all()
  end

  def list_recent(%User{}, _limit), do: {:error, :unauthorized}

  defp sanitize_details(details) when is_map(details) do
    details
    |> Map.take(@allowed_detail_keys ++ Enum.map(@allowed_detail_keys, &Atom.to_string/1))
    |> Enum.into(%{}, fn {key, value} -> {to_string(key), safe_value(value)} end)
  end

  defp sanitize_details(_), do: %{}
  defp safe_value(value) when is_binary(value), do: String.slice(value, 0, 500)
  defp safe_value(value) when is_atom(value), do: Atom.to_string(value)
  defp safe_value(value) when is_number(value) or is_boolean(value), do: value
  defp safe_value(value), do: inspect(value, limit: 10, printable_limit: 500)
end
