# Directory Layout

How the server filesystem is organized.

## Core Principle

**Infrastructure and application code are kept separate.** Infra configs live under `/opt/`, app code lives under `~/code/`. They are managed independently.

## Structure

```
/opt/docker-infra/
├── docker-compose.yml       # All infra service definitions
└── .env                     # Secrets & config (never committed)

/data/
└── postgres/                # PostgreSQL persistent data (bind-mounted)

~/INFRA/
└── DocerPostgreINFRA.md     # Legacy infra reference (being replaced by this repo)
~/code/                       # or ~/projects/code/
├── gmaps-timeline-viewer/   # Travel Map Intelligence (Node server.mjs :8000)
├── postgresql-mcp/          # Read-only Postgres MCP
└── …                        # Other standalone apps
```

## Conventions

- **`/opt/docker-infra/`** — Single source of truth for infrastructure containers (postgres, pgadmin, etc.)
- **`/data/<service>/`** — Persistent data directories, bind-mounted into containers. Survives container rebuilds.
- **`~/code/` / `~/projects/code/`** — Application code and standalone services (each may have their own `docker-compose.yml` or host process)
- **Travel Map Intelligence** — Hosted as `node server.mjs` on `127.0.0.1:8000`, exposed with `tailscale serve --https=8443` (see [travel-map-intelligence.md](travel-map-intelligence.md)). Not in `/opt/docker-infra/`.
- **`.env` files** — Never committed. Every project includes a `.env.example` template.
