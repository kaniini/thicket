defmodule Thicket.Release do
  @moduledoc false

  @app :thicket

  def migrate do
    load_app()

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def create_invite(max_uses \\ 1) do
    case Thicket.Identity.create_operator_invitation(%{max_uses: max_uses}) do
      {:ok, invitation, code} ->
        IO.puts("Invitation #{invitation.id}")
        IO.puts(code)
        :ok

      {:error, changeset} ->
        raise "could not create invitation: #{inspect(changeset.errors)}"
    end
  end

  def promote_admin(email) do
    case Thicket.Identity.promote_admin(email) do
      {:ok, _user} -> :ok
      {:error, reason} -> raise "could not promote administrator: #{inspect(reason)}"
    end
  end

  defp load_app do
    Application.load(@app)
  end
end
