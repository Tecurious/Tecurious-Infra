# Adding a service to the cluster

How to onboard a new app so ArgoCD manages it. Everything lives in
`github.com/Tecurious/Tecurious-Infra` (branch `main` — always `main`).

## Layout

```
infrastructure/
├── bootstrap/root-app.yaml       # app-of-apps; points at apps/apps-onboard/
├── apps/
│   ├── apps-onboard/<app>.yaml   # Application CR for the app (one per app)
│   └── <app>/                    # workload manifests (kustomization + resources)
│       └── application.yaml      # (canonical Application CR also lives here)
└── cluster/                      # ArgoCD itself, firewall scripts, runbooks
```

## Convention (do not deviate)

- **Branch:** every Application must set `spec.source.targetRevision: main`.
  Never feature branches, never HEAD, never a tag.
- **Namespace:** each app gets its own namespace; workloads carry an explicit
  `namespace:` in metadata (ArgoCD needs it).
- **Secrets:** created out-of-band with `kubectl create secret` — never in git,
  never via kustomize secretGenerator in a tracked dir.
- **Images:** tag with semver (`v0.1.0` style), reference by tag, never `latest`.

## Steps

1. Create `infrastructure/apps/<app>/` with workload manifests + `kustomization.yaml`.
2. Create the Application CR — copy an existing one from `apps/apps-onboard/`,
   change name/path/namespace only. `targetRevision` stays `main`.
3. Apply the Application CR once manually:
   `kubectl apply -f infrastructure/apps/<app>/application.yaml`
4. Commit + push to `main`. ArgoCD auto-syncs within ~3 min.
5. Verify: `kubectl -n devpool get applications` → app shows Synced/Healthy.

## Gotchas (all learned the hard way)

- **Jobs are immutable.** To change a Job (e.g. migrate job), delete it before
  re-sync: `kubectl -n <ns> delete job <name>`.
- **Application specs self-heal.** `kubectl patch` of an Application spec gets
  reverted by ArgoCD. Change the spec in the repo AND `kubectl apply` the file.
- **ArgoCD caches manifests in Redis.** If a sync keeps using an old revision
  despite git being updated, flush: `kubectl -n devpool delete pod -l app.kubernetes.io/name=argocd-redis`.
- **Secrets don't cross namespaces.** If a Job in ns X needs a secret from ns Y,
  copy it (out-of-band, never commit).
- **`%` in URLs breaks Alembic** (configparser interpolation). Use
  `?options=-csearch_path=a,b` — no percent-encoding.
- **pgvector lives in `public`.** Any role with a custom search_path must include
  `public` to see the `vector` type.

## Image delivery (current state)

Images are built locally (`docker build`) and imported into k3s containerd:

```
docker save <image:tag> | sudo /usr/bin/ctr -a /run/k3s/containerd/containerd.sock -n k8s.io images import -
```

This means images are lost on node rebuild. TODO: GitHub Actions → ghcr.io
build-and-push, then bump the tag in this repo (which triggers ArgoCD).
