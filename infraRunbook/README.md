# Infra Runbook

Reference documentation for the homelab server infrastructure — Docker, networking, deployment, and operations.

## Documents

| Doc | Description |
|---|---|
| [Directory Layout](directory-layout.md) | Server folder structure and separation conventions |
| [Docker Networking](docker-networking.md) | Global network setup and container communication |
| [Adding a Service](adding-a-service.md) | Step-by-step guide for onboarding a new container |
| [PostgreSQL MCP](postgres-mcp.md) | Deploy and operate the read-only Postgres MCP server for AI agents |
| [Travel Map Intelligence](travel-map-intelligence.md) | Timeline viewer on `:8000` / Tailscale `:8443` (geocode + OSRM route fill) |
| [Tailscale Networking](tailscale-networking.md) | Mesh VPN, remote access, and `tailscale serve` |
| [RClone Hero to Zero](../Concepts/Rclone/RClone%20Hero%20to%20Zero.md) | Server “upload hub” pattern + cheat sheet for Google Drive |

## Quick Reference

| Property | Value |
|---|---|
| OS | Ubuntu 24.04 LTS |
| Runtime | Docker 29.x |
| Compose | Docker Compose v5.x |
| Remote Access | Tailscale |
| Infra Root | `/opt/docker-infra/` |
