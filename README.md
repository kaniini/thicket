# Thicket

## Development

Requirements: Elixir 1.15+, Erlang/OTP 23+, PostgreSQL 13+, and a C compiler for
Argon2.

```sh
mix setup
mix thicket.invite
mix phx.server
```

The invite task prints a one-time invite code. After registering, promote the
first administrator with `mix thicket.admin EMAIL`. Development uploads use
`priv/static/uploads`; the directory is intentionally not committed.

Run `mix precommit` before submitting a change.

## Docker Compose

The included Compose stack runs Thicket with PostgreSQL, persistent local
uploads, and Mailpit for development email:

```sh
docker compose up --build
```

Thicket is available at <http://localhost:4000> and captured email at
<http://localhost:8025>. Database migrations run automatically when the app
container starts. Create the first invite and promote an administrator with:

```sh
docker compose exec app bin/thicket rpc 'Thicket.Release.create_invite()'
docker compose exec app bin/thicket rpc 'Thicket.Release.promote_admin("you@example.com")'
```

The bundled secrets and database password are development defaults. Set
`SECRET_KEY_BASE`, `FEDERATION_KEY_BASE`, and `POSTGRES_PASSWORD` in the
environment before using this stack anywhere externally reachable. Set
`PHX_HOST`, `PHX_SCHEME`, and `PHX_URL_PORT` together before first boot because
the ActivityPub public origin is permanent.

## Production

Build the included `Dockerfile` or an ordinary `mix release`. Required runtime
configuration is:

- `DATABASE_URL`, `SECRET_KEY_BASE`, `FEDERATION_KEY_BASE`, `PHX_HOST`, and optionally `PORT`,
  `PHX_SCHEME`, and `PHX_URL_PORT`;
- `SMTP_RELAY`, with optional `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, and
  `SMTP_SSL`, and `SMTP_TLS` (`always`, `if_available`, or `never`);
- `S3_ENDPOINT`, `S3_PUBLIC_BASE_URL`, `S3_BUCKET`, `S3_ACCESS_KEY_ID`, and
  `S3_SECRET_ACCESS_KEY`, with optional `S3_REGION`.

`STORAGE_BACKEND=local` selects filesystem storage for a deliberately
persistent-volume-backed deployment. S3-compatible storage is the production
default.

Health probes are available at `/health/live` and `/health/ready`.

## License

Thicket is licensed under the GNU Affero General Public License, version 3 only
(`AGPL-3.0-only`).
