# PostgreSQL MCP — Deployment & Operations

End-to-end guide for deploying and operating the read-only PostgreSQL MCP server on the homelab. This service gives AI agents (Cursor, Claude Desktop, etc.) safe, read-only access to Postgres for debugging and exploration.

**Source repo:** [github.com/vallaksa/postgresql-mcp](https://github.com/vallaksa/postgresql-mcp)

---

## What It Is

`postgresql-mcp` is a [Model Context Protocol](https://modelcontextprotocol.io) server that exposes read-only PostgreSQL access to LLM agents. It is **not** the application data layer — DevStorm and future apps write data through their own services (SQLAlchemy today, data-provider microservice later).

| Role | Owner | Access |
|------|-------|--------|
| **Application CRUD** | DevStorm / data-provider | Full read/write via app code |
| **Agent debugging** | `postgresql-mcp` | Read-only SQL, schema discovery |
| **Database storage** | `postgres` container in `/opt/docker-infra` | Persistent data in `/data/postgres/` |

### MCP tools exposed

| Tool | Purpose |
|------|---------|
| `query` | Read-only SQL (`SELECT`, `WITH`, `EXPLAIN`, `SHOW`) inside `BEGIN READ ONLY` |
| `list_tables` | List base tables in a schema |
| `describe_table` | Column names, types, nullability, defaults |
| Resource `table-schema` | Per-table column metadata as JSON |

### Safety guarantees

- SQL keyword blocklist rejects `INSERT`, `UPDATE`, `DELETE`, DDL, etc.
- Every query runs inside `BEGIN TRANSACTION READ ONLY`
- Row cap per query (default 100, max 1000 via `MCP_MAX_ROWS`)
- DB user `mcp_reader` has `SELECT` only — never use the `postgres` superuser

---

## Architecture on This Server

```mermaid
flowchart TB
  subgraph tailnet [Tailscale tailnet]
    Mac[MacBook / Cursor]
  end

  subgraph server [Linux server]
    TS["tailscale serve :443"]
    MCP["postgres-mcp :3000\n127.0.0.1 only"]
    PG[("postgres :5432\npgvector/pgvector:pg16")]
    PGA[pgadmin :5050]
  end

  Mac -->|"HTTPS + Bearer token"| TS
  TS -->|"http://127.0.0.1:3000"| MCP
  MCP -->|"mcp_reader@postgres:5432"| PG
  PGA --> PG
```

### Where things live

| Component | Path / container | Network |
|-----------|------------------|---------|
| Postgres | `/opt/docker-infra/` → `postgres` | `global-network` |
| pgAdmin | `/opt/docker-infra/` → `pgadmin` | `global-network` |
| **PostgreSQL MCP** | `~/code/postgresql-mcp/` → `postgres-mcp` | `global-network` |
| Postgres data | `/data/postgres/` (bind mount) | — |

**Placement decision:** MCP is a **standalone app** (own repo, own image, own deploy cycle) attached to `global-network` so it reaches `postgres` by container name. It does **not** belong in `/opt/docker-infra/` — that directory is for shared infra like the database itself.

See also: [Directory Layout](directory-layout.md), [Docker Networking](docker-networking.md), [Adding a Service](adding-a-service.md) (all in this runbook).

---

## Connection Strings by Context

| From | Postgres URL | MCP URL |
|------|--------------|---------|
| Host machine (bare metal) | `postgresql://user:pass@localhost:5432/devstrom` | `http://127.0.0.1:3000/mcp` |
| Container on `global-network` | `postgresql://user:pass@postgres:5432/devstrom` | N/A (MCP not needed inside containers) |
| Mac via Tailscale | `postgresql://user:pass@<tailscale-ip>:5432/devstrom` | `https://<server>.<tailnet>.ts.net/mcp` |

The MCP container uses the **container-to-container** Postgres URL (`postgres` hostname, not `localhost`).

---

## Prerequisites

### 1. Postgres running on `global-network`

Confirm the existing infra is healthy:

```bash
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
docker network inspect global-network --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}'
```

Expected: `postgres` and `pgadmin` on `global-network`.

### 2. `mcp_reader` database user

Create the read-only user (one-time, or after password rotation):

```bash
MCP_READER_PASSWORD='your-strong-password' docker exec -i postgres \
  psql -U postgres -d devstrom -v ON_ERROR_STOP=1 \
  -c "SET mcp.reader_password = '${MCP_READER_PASSWORD}'" \
  -f - < ~/code/postgresql-mcp/scripts/setup_readonly_user.sql
```

Or from the repo on the server:

```bash
cd ~/code/postgresql-mcp
MCP_READER_PASSWORD='your-strong-password' psql -h localhost -U postgres -d devstrom \
  -v ON_ERROR_STOP=1 -f scripts/setup_readonly_user.sql
```

### 3. Grant SELECT on new tables

Whenever DevStorm (or another app) adds tables via Alembic, re-grant so `mcp_reader` can see them:

```bash
docker exec -i postgres psql -U postgres -d devstrom <<'SQL'
GRANT CONNECT ON DATABASE devstrom TO mcp_reader;
GRANT USAGE ON SCHEMA public TO mcp_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO mcp_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO mcp_reader;
SQL
```

> **Note:** `information_schema` only lists tables the user has `SELECT` on. If `list_tables` returns fewer tables than expected, run the grants above.

### 4. Clone / update the repo

```bash
cd ~/code
git clone https://github.com/vallaksa/postgresql-mcp.git   # first time
cd postgresql-mcp
git pull origin main
```

Ensure `main` includes the HTTP transport and Dockerfile (see [PR #1](https://github.com/vallaksa/postgresql-mcp/pull/1) or later).

---

## Deployment

### Step 1 — Create `docker-compose.yml`

In `~/code/postgresql-mcp/docker-compose.yml`:

```yaml
services:
  postgres-mcp:
    build: .
    image: postgresql-mcp:latest
    container_name: postgres-mcp
    restart: unless-stopped
    env_file: .env
    ports:
      - "127.0.0.1:3000:3000"
    networks:
      - global-network
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:3000/health"]
      interval: 30s
      timeout: 5s
      retries: 3

networks:
  global-network:
    external: true
```

**Port binding `127.0.0.1:3000`:** MCP is not exposed on the LAN. Remote access goes through Tailscale serve only.

### Step 2 — Create `.env` (server secrets, never commit)

```env
DATABASE_URL=postgresql://mcp_reader:<MCP_READER_PASSWORD>@postgres:5432/devstrom
MCP_API_KEY=<LONG_RANDOM_SECRET>
MCP_MAX_ROWS=100
HOST=0.0.0.0
PORT=3000
MCP_HTTP_PATH=/mcp
```

Generate a strong API key:

```bash
openssl rand -hex 32
```

### Step 3 — Build and start

```bash
cd ~/code/postgresql-mcp
docker compose up -d --build
docker compose logs -f postgres-mcp
```

Expected log line:

```
[postgresql-mcp] Streamable HTTP listening on http://0.0.0.0:3000/mcp
```

### Step 4 — Verify on the server

```bash
# Health endpoint (no auth required)
curl -s http://127.0.0.1:3000/health
# → {"status":"ok","transport":"streamable-http"}

# Confirm container is on global-network
docker network inspect global-network --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' | grep postgres-mcp

# Confirm MCP can reach postgres (check logs for connection errors)
docker compose logs postgres-mcp --tail 20
```

---

## Expose via Tailscale

Use **Tailscale serve** (tailnet-only). Do **not** use `tailscale funnel` (public internet) for a service with database read access.

```bash
# On the server — proxy HTTPS on your tailnet to local MCP
sudo tailscale serve --bg --https=443 http://127.0.0.1:3000
```

Check status:

```bash
tailscale serve status
```

Your MCP endpoint becomes:

```
https://<server-hostname>.<tailnet-name>.ts.net/mcp
```

Verify from your Mac (must be on the same tailnet):

```bash
curl -s https://<server-hostname>.<tailnet-name>.ts.net/health
```

See [Tailscale Networking](tailscale-networking.md) for mesh VPN background and ACL notes.

---

## Client Configuration

### Remote MCP (recommended for daily use)

Point any MCP client at the Tailscale URL. **No database credentials in client config** — only the API key.

**Cursor** — project `.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "postgresql": {
      "url": "https://<server-hostname>.<tailnet-name>.ts.net/mcp",
      "headers": {
        "Authorization": "Bearer ${env:POSTGRES_MCP_TOKEN}"
      }
    }
  }
}
```

Set the token on your Mac:

```bash
# Add to ~/.zshrc or ~/.bashrc
export POSTGRES_MCP_TOKEN="<same value as MCP_API_KEY on server>"
```

Then refresh MCP in **Cursor → Settings → MCP**.

### Fallback: mcp-remote bridge

If the remote URL has issues in Agent mode, bridge HTTP to stdio:

```json
{
  "mcpServers": {
    "postgresql": {
      "command": "npx",
      "args": [
        "-y",
        "mcp-remote",
        "https://<server-hostname>.<tailnet-name>.ts.net/mcp",
        "--header",
        "Authorization:Bearer ${env:POSTGRES_MCP_TOKEN}"
      ]
    }
  }
}
```

### Local stdio (dev on the server only)

For quick debugging directly on the server:

```bash
cd ~/code/postgresql-mcp
export DATABASE_URL="postgresql://mcp_reader:password@localhost:5432/devstrom"
npm run build
npm start
```

Or via Docker exec:

```bash
docker exec -it postgres-mcp node dist/index.js stdio
```

---

## End-to-End Smoke Test

Run this checklist after first deploy or any upgrade.

| # | Check | Command | Expected |
|---|-------|---------|----------|
| 1 | Container running | `docker ps \| grep postgres-mcp` | `Up` status |
| 2 | Health | `curl -s http://127.0.0.1:3000/health` | `"status":"ok"` |
| 3 | Network | `docker network inspect global-network` | `postgres-mcp` listed |
| 4 | Tailscale | `curl -s https://<server>.ts.net/health` (from Mac) | `"status":"ok"` |
| 5 | MCP tools | Ask Cursor agent: "list tables in postgres" | Returns table list |
| 6 | Read data | Ask Cursor agent: "show latest 3 runs" | Returns rows from `runs` |
| 7 | Write blocked | MCP `query` with `INSERT` | Error: read-only SQL only |

---

## Operations & Maintenance

### Deploy lifecycle

MCP has its **own deploy cycle**, separate from Postgres and DevStorm:

```mermaid
flowchart LR
  Code[MCP code change] --> PR[Merge to main]
  PR --> Pull[git pull on server]
  Pull --> Build[docker compose up -d --build]
  Build --> Verify[curl /health]
```

```bash
cd ~/code/postgresql-mcp
git pull origin main
docker compose up -d --build
curl -s http://127.0.0.1:3000/health
```

### What triggers what

| Event | Action | Rebuild MCP? |
|-------|--------|--------------|
| MCP code change | `git pull` + `docker compose up -d --build` | Yes |
| DevStorm schema change (Alembic) | Run migration in DevStorm | No — but re-grant `mcp_reader` |
| DevStorm app deploy | Deploy DevStorm image | No |
| Postgres upgrade | `/opt/docker-infra` maintenance | No |
| Rotate `MCP_API_KEY` | Update server `.env` + client `POSTGRES_MCP_TOKEN`, restart MCP | Restart only |
| Rotate `mcp_reader` password | Update Postgres role + server `.env` `DATABASE_URL`, restart MCP | Restart only |

### Restart / stop

```bash
cd ~/code/postgresql-mcp
docker compose restart postgres-mcp
docker compose stop postgres-mcp
docker compose down          # removes container, not the image
```

### View logs

```bash
docker compose logs -f postgres-mcp
docker compose logs postgres-mcp --tail 50
```

### No persistent volume needed

MCP is stateless — it holds no data. Rebuilding the container does not affect Postgres data in `/data/postgres/`.

---

## Security Checklist

- [ ] `mcp_reader` user only — never `postgres` superuser in `DATABASE_URL`
- [ ] Strong `MCP_API_KEY` (32+ random bytes)
- [ ] Port `3000` bound to `127.0.0.1` on the host
- [ ] Tailscale **serve**, not **funnel**
- [ ] Tailscale ACL restricts who can reach the server on port 443
- [ ] `.env` never committed to git
- [ ] Re-grant `SELECT` after new tables are created
- [ ] Default password `mcp_reader_change_me` rotated before production use

---

## Troubleshooting

### `list_tables` returns fewer tables than expected

`mcp_reader` lacks `SELECT` on new tables. Run the grant block in [Prerequisites §3](#3-grant-select-on-new-tables).

### MCP container can't connect to Postgres

```bash
# Confirm both on global-network
docker network inspect global-network --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}'

# Test DNS from MCP container
docker exec postgres-mcp wget -qO- http://127.0.0.1:3000/health

# Check DATABASE_URL uses hostname `postgres`, not `localhost`
docker exec postgres-mcp env | grep DATABASE_URL
```

Inside a container, `localhost` refers to the container itself, not the host or the postgres container.

### `401 Unauthorized` from MCP

- `Authorization: Bearer <token>` header must match `MCP_API_KEY` in server `.env`
- Check for trailing whitespace in `.env`
- Restart after `.env` change: `docker compose restart postgres-mcp`

### Cursor doesn't see MCP tools

1. Settings → MCP → confirm `postgresql` is enabled (green)
2. Refresh MCP or restart Cursor
3. For remote URL issues, try the `mcp-remote` fallback above
4. Ensure only one `postgresql` entry (not duplicated in project + global config)

### Health check fails

```bash
docker compose logs postgres-mcp
docker exec postgres-mcp wget -qO- http://127.0.0.1:3000/health
```

Common causes: port conflict on 3000, missing `DATABASE_URL`, Postgres unreachable.

### Tailscale serve not working

```bash
tailscale serve status
tailscale status
curl -v https://<server>.ts.net/health
```

Ensure Tailscale is running on both server and client. See [Tailscale Networking](tailscale-networking.md).

---

## Environment Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | — | Postgres connection string (server-side only) |
| `MCP_POSTGRES_URL` | — | Alias for `DATABASE_URL` |
| `MCP_API_KEY` | — | Bearer token for HTTP auth (required on non-loopback bind) |
| `MCP_MAX_ROWS` | `100` | Max rows per query (max `1000`) |
| `HOST` | `0.0.0.0` | HTTP bind address inside container |
| `PORT` | `3000` | HTTP port |
| `MCP_HTTP_PATH` | `/mcp` | Streamable HTTP endpoint path |
| `MCP_TRANSPORT` | `stdio` | `stdio` or `http` (Dockerfile sets `http`) |

---

## Related Docs

| Doc | Relevance |
|-----|-----------|
| [Docker Networking](docker-networking.md) | `global-network`, container DNS |
| [Adding a Service](adding-a-service.md) | General onboarding checklist |
| [Directory Layout](directory-layout.md) | `/opt/` vs `~/code/` separation |
| [Tailscale Networking](tailscale-networking.md) | Remote access, `tailscale serve` |
| [postgresql-mcp README](https://github.com/vallaksa/postgresql-mcp/blob/main/README.md) | Upstream tool docs and client examples |
