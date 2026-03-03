# Docker Networking

How containers communicate on this server.

## Global Network

A single shared bridge network called `global-network` connects all infrastructure services. It was created once and is never destroyed by compose:

```bash
docker network create global-network
```

## Current State

### Networks on this server

```bash
docker network ls
```

| Network | Driver | Purpose |
|---|---|---|
| `global-network` | bridge | Shared infra network — all services join this |
| `git-activity-bot_default` | bridge | Auto-created by the git-bot compose (standalone) |
| `bridge` | bridge | Docker default (unused) |
| `host` | host | Docker default |

### Containers on `global-network`

To see which containers are connected and their assigned IPs:

```bash
docker network inspect global-network --format '{{range .Containers}}{{.Name}} → {{.IPv4Address}}{{"\n"}}{{end}}'
```

Currently running:

| Container | Image | Ports |
|---|---|---|
| `postgres` | `pgvector/pgvector:pg16` | 5432 |
| `pgadmin` | `dpage/pgadmin4` | 5050 |

To see full network details (subnet, gateway, driver):

```bash
docker network inspect global-network
```

## How It Works

- Any container attached to `global-network` can reach others **by container name** — no IP addresses needed.
- DNS resolution is automatic. The container name `postgres` resolves to its assigned IP for any container on the same network.

## Connecting From Different Contexts

| From | Connection String |
|---|---|
| Host machine (bare metal) | `postgresql://user:pass@localhost:5432/db` |
| Another container on `global-network` | `postgresql://user:pass@postgres:5432/db` |
| External (via Tailscale) | `postgresql://user:pass@<tailscale-ip>:5432/db` |

## Compose Configuration

To attach any service to the global network, add this to its `docker-compose.yml`:

```yaml
services:
  my-service:
    # ... service config ...
    networks:
      - global-network

networks:
  global-network:
    external: true
```

`external: true` tells Compose the network already exists — it won't try to create or destroy it.

## Useful Commands

```bash
# List all networks
docker network ls

# Inspect a network (see connected containers, subnet, gateway)
docker network inspect global-network

# See which containers are on a network (compact)
docker network inspect global-network --format '{{range .Containers}}{{.Name}} → {{.IPv4Address}}{{"\n"}}{{end}}'

# Check which networks a specific container is on
docker inspect postgres --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}'

# Test connectivity between containers
docker exec -it pgadmin ping postgres

# List all running containers with ports
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

# Manually connect an existing container to the network
docker network connect global-network <container-name>

# Disconnect a container from the network
docker network disconnect global-network <container-name>
```
