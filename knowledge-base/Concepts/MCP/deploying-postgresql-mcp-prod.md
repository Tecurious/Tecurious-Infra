# Deploying PostgreSQL MCP to Production (Docker + Cursor)

A practical record of how we deployed `postgresql-mcp` on **saiserver** in Docker, exposed it via Tailscale, and connected Cursor on a Mac.

**Repo:** [github.com/vallaksa/postgresql-mcp](https://github.com/vallaksa/postgresql-mcp)  
**Related:** [Building PostgreSQL MCP](building-postgresql-mcp.md) · [Infra runbook](../../infraRunbook/postgres-mcp.md) · [MCP Zero-to-Hero](zero_to_hero.md)

---

## What we deployed

| Piece | Value |
|-------|-------|
| Server | `saiserver` (Ubuntu, Docker) |
| MCP container | `postgres-mcp` on `global-network` |
| MCP transport | Streamable HTTP on port `3000` |
| Remote access | Tailscale Serve → `https://<magicdns-hostname>/mcp` |
| Client | Cursor on Mac via `url` + Bearer token |
| Database | Existing `postgres` container (`devstrom` DB) |
| DB user | `mcp_reader` (read-only) |

MCP is **not** in `/opt/docker-infra/`. It lives in `~/projects/code/postgresql-mcp/` as a standalone app with its own deploy cycle.

---

## Architecture

```mermaid
flowchart TB
  subgraph mac [Mac — Cursor]
    Cursor[Cursor MCP client]
  end

  subgraph tailnet [Tailscale tailnet]
    TS["tailscale serve :443"]
  end

  subgraph saiserver [saiserver]
    MCP["postgres-mcp :3000\n127.0.0.1 bind"]
    PG[("postgres :5432")]
  end

  Cursor -->|"HTTPS + Bearer token"| TS
  TS -->|"http://127.0.0.1:3000"| MCP
  MCP -->|"mcp_reader@postgres:5432"| PG
```

**Security layers:**

1. MCP port `3000` bound to `127.0.0.1` on the host (not LAN)
2. `MCP_API_KEY` Bearer auth on `/mcp`
3. SQL keyword guard + `BEGIN READ ONLY` transactions
4. `mcp_reader` Postgres role — `SELECT` only

---

## Prerequisites

- [x] Postgres running in Docker (`postgres` container on `global-network`)
- [x] `global-network` exists: `docker network create global-network`
- [x] Repo cloned: `~/projects/code/postgresql-mcp`
- [x] Tailscale on server and Mac (same tailnet)

---

## Step 1 — Create the read-only DB user

On saiserver:

```bash
cd ~/projects/code/postgresql-mcp

MCP_READER_PASSWORD='<strong-password>' docker exec -i postgres \
  psql -U postgres -d devstrom -v ON_ERROR_STOP=1 \
  -c "SET mcp.reader_password = '${MCP_READER_PASSWORD}'" \
  -f - < scripts/setup_readonly_user.sql
```

Verify:

```bash
docker exec -i postgres psql -U mcp_reader -d devstrom -c "SELECT 1"
```

If the password contains `@`, you must URL-encode it in connection strings as `%40` (see [Gotchas](#gotchas-we-hit)).

---

## Step 2 — Docker Compose setup

Copy the example and create secrets:

```bash
cd ~/projects/code/postgresql-mcp
cp docker-compose.example.yml docker-compose.yml
cp .env.example .env
```

Edit `.env` (never commit):

```env
DATABASE_URL=postgresql://mcp_reader:<password-with-%40-for-@>@postgres:5432/devstrom
MCP_API_KEY=<openssl rand -hex 32>
MCP_MAX_ROWS=100
HOST=0.0.0.0
PORT=3000
MCP_HTTP_PATH=/mcp
```

**Important:** use hostname `postgres` (container name on `global-network`), not `localhost`.

`docker-compose.yml` must be **lowercase** — Linux is case-sensitive. `Docker-compose.yml` will not be picked up by `docker compose`.

---

## Step 3 — Build and start

```bash
cd ~/projects/code/postgresql-mcp
docker compose up -d --build
docker compose logs -f postgres-mcp
```

Expected log:

```text
[postgresql-mcp] Streamable HTTP listening on http://0.0.0.0:3000/mcp
```

---

## Step 4 — Verify on the server

### Health (no auth)

```bash
curl -s http://127.0.0.1:3000/health
# → {"status":"ok","transport":"streamable-http"}
```

### Network

```bash
docker network inspect global-network --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' | grep postgres-mcp
```

### Auth

```bash
export MCP_API_KEY=$(grep '^MCP_API_KEY=' .env | cut -d= -f2-)

# No token → 401
curl -s -o /dev/null -w "%{http_code}\n" -X POST http://127.0.0.1:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"initialize","params":{},"id":1}'

# With token + Accept header → 200 (SSE body)
curl -s -X POST http://127.0.0.1:3000/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer $MCP_API_KEY" \
  -d '{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}},"id":1}'
```

### Database round-trip

```bash
curl -s -X POST http://127.0.0.1:3000/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer $MCP_API_KEY" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_tables","arguments":{"schema":"public"}},"id":2}'
```

Should return table names, not a password error.

---

## Step 5 — Expose via Tailscale Serve

Enable Serve in the Tailscale admin UI first (tailnet admin must approve):

```
https://login.tailscale.com/f/serve?node=<your-node-id>
```

Then on saiserver:

```bash
sudo tailscale serve --bg --https=443 http://127.0.0.1:3000
tailscale serve status
```

Our endpoint:

| Endpoint | URL |
|----------|-----|
| Health | `https://<magicdns-hostname>/health` |
| MCP | `https://<magicdns-hostname>/mcp` |

Verify from Mac:

```bash
curl -s https://<magicdns-hostname>/health
```

Use **serve** (tailnet-only), not **funnel** (public internet).

### SSH tunnel fallback

If Tailscale Serve is unavailable:

```bash
# On Mac — keep terminal open
ssh -N -L 3000:127.0.0.1:3000 vallaksa@saiserver
```

Then point Cursor at `http://127.0.0.1:3000/mcp`.

---

## Step 6 — Configure Cursor

### Why our config looks different from other MCP servers

Most MCP servers in `.cursor/mcp.json` use the **stdio** pattern:

```json
"sequential-thinking": {
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
}
```

Cursor spawns a **local process** and talks over stdin/stdout. That works when the tool runs on your Mac.

Our Postgres MCP runs **remotely on saiserver in Docker**. The database URL and credentials stay on the server. Cursor only needs the HTTP endpoint and an API key.

| Pattern | When to use |
|---------|-------------|
| `command` + `npx` | Tool runs locally (github, memory, playwright, …) |
| `url` + `headers` | Tool runs remotely (our Docker + Tailscale deploy) |
| `npx mcp-remote` | Bridge — looks like stdio but proxies to remote HTTP |

### Recommended Cursor config (remote HTTP)

On your Mac, set the token (same value as `MCP_API_KEY` on the server):

```bash
# ~/.zshrc
export POSTGRES_MCP_TOKEN="<your-MCP_API_KEY>"
```

In project `.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "postgresql": {
      "url": "https://<magicdns-hostname>/mcp",
      "headers": {
        "Authorization": "Bearer ${env:POSTGRES_MCP_TOKEN}"
      }
    }
  }
}
```

Restart Cursor → **Settings → MCP** → `postgresql` should be green.

### Alternative: npx bridge (stdio-style)

```json
"postgresql": {
  "command": "npx",
  "args": [
    "-y",
    "mcp-remote",
    "https://<magicdns-hostname>/mcp",
    "--header",
    "Authorization:Bearer ${env:POSTGRES_MCP_TOKEN}"
  ]
}
```

### What NOT to use in production

This was our old broken config — do not use:

```json
"postgresql": {
  "command": "node",
  "args": ["/path/to/postgresql-mcp/dist/index.js"],
  "env": {
    "MCP_POSTGRES_URL": "postgresql://mcp_reader:password@localhost:5432/devstrom"
  }
}
```

Problems: runs MCP locally, `localhost` points at the Mac not saiserver, DB creds in client config.

---

## Step 7 — Smoke test in Cursor

Ask the agent:

1. *"List tables using the postgresql MCP"*
2. *"Describe the runs table"*
3. *"Show the latest 3 rows from runs"*

---

## Gotchas we hit

| Symptom | Cause | Fix |
|---------|-------|-----|
| `no configuration file provided` | File named `Docker-compose.yml` (wrong case) | Rename to `docker-compose.yml` |
| `password authentication failed for user "mcp_reader"` | `@` in password breaks URL parsing (`Sai@pass` → password `Sai`) | URL-encode: `Sai%40pass` in `DATABASE_URL` |
| `401` with real-looking curl | Literal `<your-MCP_API_KEY>` or wrong token | Use `$(grep '^MCP_API_KEY=' .env \| cut -d= -f2-)` |
| `406` on MCP POST | Missing `Accept: application/json, text/event-stream` | Add Accept header (auth passed — 406 is protocol, not auth) |
| `Serve is not enabled on your tailnet` | Tailscale admin hasn't enabled Serve | Visit admin link from CLI error message |
| Empty `list_tables` | `mcp_reader` lacks SELECT on new tables | Re-grant after Alembic migrations |
| `localhost` in container URL | Inside Docker, localhost is the MCP container itself | Use `@postgres:5432` |

---

## Ongoing operations

### Upgrade MCP

```bash
cd ~/projects/code/postgresql-mcp
git pull origin main
docker compose up -d --build
curl -s http://127.0.0.1:3000/health
```

### Re-grant after new tables

```bash
docker exec -i postgres psql -U postgres -d devstrom <<'SQL'
GRANT SELECT ON ALL TABLES IN SCHEMA public TO mcp_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO mcp_reader;
SQL
```

### Rotate API key

1. Update `MCP_API_KEY` in server `.env`
2. Update `POSTGRES_MCP_TOKEN` on Mac
3. `docker compose up -d --force-recreate`
4. Restart Cursor

### Disable Tailscale Serve

```bash
sudo tailscale serve --https=443 off
```

---

## Deploy checklist

```text
[ ] mcp_reader created with strong password
[ ] .env created (DATABASE_URL uses postgres hostname, %40 for @)
[ ] docker-compose.yml (lowercase) from example
[ ] docker compose up -d --build
[ ] curl /health → ok
[ ] postgres-mcp on global-network
[ ] MCP initialize + list_tables work with Bearer token
[ ] Tailscale serve enabled and status shows proxy
[ ] curl https://<magicdns-hostname>/health from Mac → ok
[ ] POSTGRES_MCP_TOKEN set on Mac
[ ] .cursor/mcp.json updated with url transport
[ ] Cursor MCP green, agent can query tables
```

---

## Related docs

| Doc | Purpose |
|-----|---------|
| [building-postgresql-mcp.md](building-postgresql-mcp.md) | How the server code works |
| [zero_to_hero.md](zero_to_hero.md) | MCP protocol concepts |
| [infraRunbook/postgres-mcp.md](../../infraRunbook/postgres-mcp.md) | Ops reference, troubleshooting |
| [infraRunbook/docker-networking.md](../../infraRunbook/docker-networking.md) | `global-network` details |
| [infraRunbook/tailscale-networking.md](../../infraRunbook/tailscale-networking.md) | Tailscale serve background |
