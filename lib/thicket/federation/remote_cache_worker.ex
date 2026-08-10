defmodule Thicket.Federation.RemoteCacheWorker do
  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 86_400]

  @impl Oban.Worker
  def perform(_job) do
    {_count, _} = Thicket.Federation.RemoteActors.evict_stale()
    :ok
  end
end
