# Tecurious-Infra

Personal infrastructure and knowledge repository, split into two top-level domains:

```
Tecurious-Infra/
├── knowledge-base/    # Documentation: runbooks, concepts, notes on what I learn
└── infrastructure/    # Declarative cluster/infra definitions, managed via GitOps
```

## knowledge-base/

Documentation of technologies learned and infrastructure configurations, organized by topic. Each folder represents a distinct domain of knowledge:

```
knowledge-base/
├── infraRunbook/   # Server, Docker, networking, remote desktop, deployment, and operations
├── databases/      # PostgreSQL, pgvector, Redis, etc.
├── languages/      # Python, JavaScript, Go, and language-specific notes
├── frameworks/     # Web frameworks, libraries, and tooling
├── devops/         # CI/CD, monitoring, automation
├── ai-ml/          # Machine learning, LLMs, embeddings, agents
├── Concepts/       # Topic deep-dives (MCP, Rclone, ...)
└── misc/           # Everything else
```

> Folders are created as needed. This is a living document that grows with what I learn.

## infrastructure/

Declarative definitions for cluster bootstrap and application workloads, intended to be driven by ArgoCD (app-of-apps pattern).

```
infrastructure/
├── bootstrap/
│   └── root-app.yaml          # ArgoCD root Application (app-of-apps entry point; placeholder)
├── cluster/
│   └── k3s-argocd/
│       ├── kustomization.yaml # ArgoCD install manifest (upstream stable) + NodePort patch
│       └── nodeport-patch.yaml# argocd-server → NodePort 30080 (http) / 30443 (https)
└── apps/                      # Per-application manifests, picked up by root-app (to be populated)
```

### Cluster bootstrap (k3s + ArgoCD)

1. Install k3s on the target node.
2. Apply the ArgoCD install with the NodePort patch:

   ```bash
   kubectl apply -k infrastructure/cluster/k3s-argocd
   ```

3. Apply the root application to start the app-of-apps sync:

   ```bash
   kubectl apply -f infrastructure/bootstrap/root-app.yaml
   ```

ArgoCD UI is then reachable on node ports `30080` (HTTP) / `30443` (HTTPS).

> `root-app.yaml` is a placeholder — replace it with the real Application manifest during bootstrap.

## Conventions

- All changes go through pull requests to `main`.
- Runbooks and docs live under `knowledge-base/`; anything applied to a cluster lives under `infrastructure/`.
- Never commit secrets, tokens, or live network addresses — use placeholders (`<API_KEY>`, `<TAILSCALE_IPV4>`, etc.) and reference the secret manager instead.
