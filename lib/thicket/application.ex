defmodule Thicket.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ThicketWeb.Telemetry,
      Thicket.Repo,
      {Oban, Application.fetch_env!(:thicket, Oban)},
      {DNSCluster, query: Application.get_env(:thicket, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Thicket.PubSub},
      # Start a worker by calling: Thicket.Worker.start_link(arg)
      # {Thicket.Worker, arg},
      # Start to serve requests, typically the last entry
      ThicketWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Thicket.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ThicketWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
