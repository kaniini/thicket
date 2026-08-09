import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/thicket start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :thicket, ThicketWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :thicket, Thicket.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  federation_key_base =
    System.get_env("FEDERATION_KEY_BASE") ||
      raise "environment variable FEDERATION_KEY_BASE is missing; generate a long random secret"

  config :thicket, :federation,
    max_document_bytes: 1_048_576,
    key_base: federation_key_base

  host =
    System.get_env("PHX_HOST") ||
      raise "environment variable PHX_HOST is missing; the canonical public origin is immutable"

  port = String.to_integer(System.get_env("PORT") || "4000")

  config :thicket, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :thicket, ThicketWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  storage_backend = System.get_env("STORAGE_BACKEND") || "s3"

  case storage_backend do
    "s3" ->
      fetch_env! = fn name ->
        System.get_env(name) || raise "environment variable #{name} is required for S3 storage"
      end

      config :thicket, :storage_adapter, Thicket.Storage.S3

      config :thicket, Thicket.Storage.S3,
        endpoint: fetch_env!.("S3_ENDPOINT"),
        public_base_url: fetch_env!.("S3_PUBLIC_BASE_URL"),
        bucket: fetch_env!.("S3_BUCKET"),
        region: System.get_env("S3_REGION") || "us-east-1",
        access_key_id: fetch_env!.("S3_ACCESS_KEY_ID"),
        secret_access_key: fetch_env!.("S3_SECRET_ACCESS_KEY")

    "local" ->
      config :thicket, :storage_adapter, Thicket.Storage.Local

    other ->
      raise "unsupported STORAGE_BACKEND #{inspect(other)}"
  end

  smtp_relay = System.get_env("SMTP_RELAY") || raise "environment variable SMTP_RELAY is missing"
  smtp_username = System.get_env("SMTP_USERNAME")

  config :thicket, Thicket.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: smtp_relay,
    port: String.to_integer(System.get_env("SMTP_PORT") || "587"),
    username: smtp_username,
    password: System.get_env("SMTP_PASSWORD"),
    ssl: System.get_env("SMTP_SSL") in ~w(true 1),
    tls: :always,
    auth: if(smtp_username, do: :always, else: :never),
    retries: 2,
    no_mx_lookups: false

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :thicket, ThicketWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :thicket, ThicketWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :thicket, Thicket.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
