import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :argon2_elixir, t_cost: 1, m_cost: 8

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :thicket, Thicket.Repo,
  username: System.get_env("PGUSER") || System.get_env("USER"),
  socket_dir: System.get_env("PGHOST") || "/var/run/postgresql",
  database: "thicket_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :thicket, ThicketWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ogMM0b54dWAvvp7NqyVQ4IgzXzTwJJs9bV0U46hQvOGxnrnT5L9uqTVkFdbhtlxO",
  server: false

# In test we don't send emails
config :thicket, Thicket.Mailer, adapter: Swoosh.Adapters.Test
config :thicket, Oban, testing: :inline, queues: false, plugins: false

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
