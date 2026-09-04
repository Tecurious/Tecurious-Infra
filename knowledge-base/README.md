# knowledge-base/

Documentation: runbooks, concepts, notes on what I learn. Reference material —
nothing in here is applied to the cluster.

## Structure

```
knowledge-base/
├── infraRunbook/    # Server, k8s, Docker, networking, Tailscale, deployment ops
│   ├── adding-a-service.md        # How to onboard an app to ArgoCD (the canonical runbook)
│   ├── directory-layout.md        # Server filesystem layout (/opt, /data, ~/code)
│   ├── docker-networking.md
│   ├── postgres-mcp.md
│   └── tailscale-networking.md
├── Concepts/        # Topic deep-dives (MCP, Rclone, ...)
└── README.md
```

> Folders are created as needed. This is a living document that grows with what I learn.

## Key entry points

- **Onboarding a service to k8s** → [infraRunbook/adding-a-service.md](infraRunbook/adding-a-service.md)
- **Server filesystem layout** → [infraRunbook/directory-layout.md](infraRunbook/directory-layout.md)

## Related

Cluster/ArgoCD specifics live in [../infrastructure/README.md](../infrastructure/README.md).
