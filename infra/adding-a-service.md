# Adding a New Service

Step-by-step checklist for adding any new container to the server infrastructure.

## Decision: Infra or Standalone?

| Type | Where | When to Use |
|---|---|---|
| **Infra service** | `/opt/docker-infra/docker-compose.yml` | Shared services (databases, reverse proxies, monitoring) |
| **Standalone app** | `~/code/<project>/docker-compose.yml` | Self-contained apps with their own lifecycle |

If the service needs to talk to `postgres` or other infra containers, attach it to `global-network` regardless of where its compose file lives.

## Checklist

### 1. Add the service definition

Add to the appropriate `docker-compose.yml`:

```yaml
services:
  my-service:
    image: some-image:tag           # Or use 'build: .' for custom images
    container_name: my-service      # Explicit name for DNS resolution
    restart: unless-stopped         # Auto-restart on crash/reboot
    env_file: .env                  # Secrets from .env file
    ports:
      - "HOST_PORT:CONTAINER_PORT"  # Only if host access is needed
    volumes:
      - /data/my-service:/data      # Persistent storage if needed
    networks:
      - global-network              # Join shared network

networks:
  global-network:
    external: true
```

### 2. Configure secrets

Add any required environment variables to `.env`:

```env
MY_SERVICE_USER=admin
MY_SERVICE_PASSWORD=<password>
```

### 3. Create persistent storage (if needed)

```bash
sudo mkdir -p /data/my-service
sudo chown <container-uid>:<container-gid> /data/my-service
```

> Check the image's documentation for the correct UID. For example, PostgreSQL uses UID `999`.

### 4. Deploy

```bash
cd /opt/docker-infra   # or ~/code/<project>
docker compose up -d --build
docker compose logs -f my-service
```

### 5. Verify

```bash
docker ps                          # Confirm it's running
docker exec -it my-service sh      # Shell into the container
docker network inspect global-network  # Confirm network attachment
```

## Template

Minimal compose entry you can copy-paste:

```yaml
  new-service:
    image: IMAGE:TAG
    container_name: new-service
    restart: unless-stopped
    env_file: .env
    networks:
      - global-network
```
