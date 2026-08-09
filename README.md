# Thicket

Thicket is a cohost-inspired social publishing application. This repository is
currently implementing the local social application described by Milestone 1
of [DESIGN.md](DESIGN.md).

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

## Production

Build the included `Dockerfile` or an ordinary `mix release`. Required runtime
configuration is:

- `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, and optionally `PORT`;
- `SMTP_RELAY`, with optional `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, and
  `SMTP_SSL`;
- `S3_ENDPOINT`, `S3_PUBLIC_BASE_URL`, `S3_BUCKET`, `S3_ACCESS_KEY_ID`, and
  `S3_SECRET_ACCESS_KEY`, with optional `S3_REGION`.

`STORAGE_BACKEND=local` selects filesystem storage for a deliberately
persistent-volume-backed deployment. S3-compatible storage is the production
default.

Health probes are available at `/health/live` and `/health/ready`.

## License

Thicket is licensed under the GNU Affero General Public License, version 3 only
(`AGPL-3.0-only`).
