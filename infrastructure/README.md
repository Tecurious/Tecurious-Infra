# infrastructure/

Declarative cluster definitions, managed by ArgoCD (app-of-apps pattern).
Everything applied to the cluster comes from this directory, branch `main`.

## Current state

- **Cluster**: k3s, single node (`saiserver`)
- **ArgoCD**: namespace `devpool`, UI at `https://sai.tailaf8d25.ts.net:8443` (tailnet-only via tailscale serve)
- **Managed apps**: postgres, postgres-mcp, dev-strom (all in ArgoCD, all tracking `main`)

## Structure

```
infrastructure/
├── bootstrap/
│   └── root-app.yaml            # ArgoCD app-of-apps entry point → apps/apps-onboard/
├── apps/
│   ├── apps-onboard/            # ALL Application CRs live here (one file per app)
│   │   ├── postgres.yaml
│   │   ├── postgres-mcp.yaml
│   │   └── dev-strom.yaml
│   ├── postgres/                # workload manifests (kustomization + resources)
│   ├── postgres-mcp/
│   └── dev-strom/               # api-deployment, web-deployment, migration-job
└── cluster/
    ├── k3s-argocd/              # ArgoCD install (pinned v2.13.3) + NodePort patch
    ├── argocd-cm-defaults.yaml  # ArgoCD server config
    └── firewall-block-nodeports.sh  # tailnet-only access for NodePorts + SSH
```

## How it works

1. root-app watches `apps/apps-onboard/` on `main` (recursive).
2. Every Application CR there is auto-created/updated by ArgoCD.
3. Each Application points at its own `apps/<name>/` folder for workload manifests.
4. Any push to `main` → ArgoCD auto-syncs within ~3 minutes.

## Adding a new app

Follow the runbook: [knowledge-base/infraRunbook/adding-a-service.md](../knowledge-base/infraRunbook/adding-a-service.md)

Short version:
1. `infrastructure/apps/<app>/` — workload manifests + `kustomization.yaml`
2. `infrastructure/apps/apps-onboard/<app>.yaml` — the Application CR (copy an existing one, change name/path/namespace; `targetRevision: main` always)
3. Commit + push to `main`. ArgoCD does the rest.

## Conventions

- **Branch**: everything tracks `main`. No feature branches in ArgoCD specs.
- **Secrets**: out-of-band `kubectl create secret` only. Never in git, never committed, never in kustomize generators inside tracked dirs.
- **Images**: semver tags (`v0.1.0`), never `latest`.
- **Namespaces**: one per app; manifests carry explicit `namespace:` in metadata.
