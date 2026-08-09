defmodule Mix.Tasks.Thicket.Admin do
  use Mix.Task

  @shortdoc "Promotes an existing user to instance administrator"

  @impl true
  def run([email]) do
    Mix.Task.run("app.start")

    case Thicket.Identity.promote_admin(email) do
      {:ok, _user} -> Mix.shell().info("Promoted #{email} to administrator")
      {:error, :not_found} -> Mix.raise("no user exists with that email")
    end
  end

  def run(_args), do: Mix.raise("usage: mix thicket.admin EMAIL")
end
