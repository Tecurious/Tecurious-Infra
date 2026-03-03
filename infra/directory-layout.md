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

~/code/
├── knowledge-Base/          # This repo
├── git-activity-bot/        # Dockerized git activity bot
├── Dev-Strom/               # Application projects
├── deep-agents-lab/
└── Ollama-Guide/

~/INFRA/
└── DocerPostgreINFRA.md     # Legacy infra reference (being replaced by this repo)
```

## Conventions

- **`/opt/docker-infra/`** — Single source of truth for infrastructure containers (postgres, pgadmin, etc.)
- **`/data/<service>/`** — Persistent data directories, bind-mounted into containers. Survives container rebuilds.
- **`~/code/`** — Application code and standalone services (each may have their own `docker-compose.yml`)
- **`.env` files** — Never committed. Every project includes a `.env.example` template.
