# Infrastructure Documentation

Reference documentation for the homelab server infrastructure.

## Documents

| Doc | Description |
|---|---|
| [Directory Layout](directory-layout.md) | Server folder structure and separation conventions |
| [Docker Networking](docker-networking.md) | Global network setup and container communication |
| [Adding a Service](adding-a-service.md) | Step-by-step guide for onboarding a new container |
| [Rclone Upload Hub (Google Drive)](rclone-gdrive-upload-hub.md) | Use the server + Tailscale to upload from mounted drives to Google Drive |

## Quick Reference

| Property | Value |
|---|---|
| OS | Ubuntu 24.04 LTS |
| Runtime | Docker 29.x |
| Compose | Docker Compose v5.x |
| Remote Access | Tailscale |
| Infra Root | `/opt/docker-infra/` |
