#!/usr/bin/env bash
# ArgoCD install on k3s — no Helm, plain kubectl + kustomize (built into kubectl).
# Source of truth: this repo. Run from anywhere; paths are relative to this file.
set -euo pipefail

cd "$(dirname "$0")"

echo ">> Applying ArgoCD manifests (v2.13.3) via kustomize..."
kubectl apply -k .

echo ">> Waiting for argocd-server to be ready..."
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s

echo ">> Service:"
kubectl -n argocd get svc argocd-server

echo ">> Initial admin password (user: admin):"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
echo
