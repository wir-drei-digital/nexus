# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
mix setup                # Install deps, run migrations, build assets, seed DB
mix phx.server           # Start dev server (localhost:4000)
iex -S mix phx.server    # Start dev server with IEx console
mix test                 # Run all tests (runs ash.setup first)
mix test path/to/test.exs           # Run a single test file
mix test path/to/test.exs:42        # Run a specific test by line number
mix test --failed                   # Re-run only previously failed tests
mix format               # Format code (uses Spark.Formatter for Ash DSLs)
mix precommit            # Compile (warnings-as-errors) + unlock unused deps + format + test
mix ecto.reset           # Drop and recreate database with seeds
mix ash.setup            # Create DB, run migrations (Ash-aware)
```

## Architecture

**Ash-first Phoenix 1.8 application** using domain-driven design with PostgreSQL, LiveView, and AshAuthentication.

### Domain Layer (`lib/nexus/`)

- **`Nexus.Accounts`** — Ash Domain containing all auth-related resources
  - `User` — AshAuthentication resource with password, remember-me, API key, magic link, and email confirmation strategies
  - `Token` — JWT token storage for audit trail
  - `ApiKey` — API key hashes for programmatic access
- **`Nexus.Repo`** — AshPostgres.Repo requiring PostgreSQL with `citext` and `ash-functions` extensions
- **`Nexus.Secrets`** — Fetches token signing secrets from application config

### Web Layer (`lib/nexus_web/`)

- **Router** has two main pipelines:
  - `:browser` — session-based auth for LiveView (uses `ash_authentication_live_session`)
  - `:api` — ApiKey + Bearer token auth for JSON API
- **LiveView auth** uses `on_mount` guards: `live_user_required`, `live_user_optional`, `live_no_user` — every authenticated LiveView route must use the correct guard
- **`NexusWeb.Layouts`** is aliased in `nexus_web.ex` — use `<Layouts.app flash={@flash}>` to wrap LiveView templates
- **`core_components.ex`** provides `<.input>`, `<.icon>`, `<.link>`, forms, etc. — always use these instead of raw HTML
- **JSON API** routes via `NexusWeb.AshJsonApiRouter`

### Background Jobs

- **Oban** with Postgres notifier, default queue (10 workers), cron support
- **AshOban** for Ash-integrated background processing

### Frontend

- Tailwind CSS v4 (no `tailwind.config.js`) + daisyUI via vendor imports
- esbuild for JS bundling (es2022 target)
- LiveView-first — no separate JS framework

### Dev Tools

- `/dev/dashboard` — Phoenix LiveDashboard
- `/oban` — Oban Web UI
- `/dev/mailbox` — Swoosh email preview

## Key Conventions

- **Ash resources** are the source of truth — data access goes through Ash actions, not raw Ecto
- **Policy-based authorization** with `Ash.Policy.Authorizer` on resources
- Migrations are generated via `mix ash_postgres.generate_migrations` — resource snapshots live in `priv/resource_snapshots/`
- `precommit` alias runs in test env (configured in `cli/0`)
- Use `:req` (Req) for HTTP requests — never `:httpoison`, `:tesla`, or `:httpc`
- Refer to `AGENTS.md` for detailed Phoenix 1.8, LiveView, HEEx, and Elixir coding guidelines
