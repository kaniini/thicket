defmodule Mix.Tasks.Thicket.Invite do
  use Mix.Task

  @shortdoc "Creates an operator-issued invitation code"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    {options, _, _} = OptionParser.parse(args, strict: [max_uses: :integer])
    max_uses = Keyword.get(options, :max_uses, 1)

    case Thicket.Identity.create_operator_invitation(%{max_uses: max_uses}) do
      {:ok, _invitation, secret} ->
        Mix.shell().info(secret)

      {:error, changeset} ->
        Mix.raise("could not create invitation: #{inspect(changeset.errors)}")
    end
  end
end
