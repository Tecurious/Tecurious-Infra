#!/usr/bin/env bash
# Tailscale-only access for SSH, Ollama and k8s NodePorts. Run once per host with sudo; idempotent.
#
#   Host ports tailscale-only.service drops 22 (SSH) and 11434 (Ollama) on every interface
#              except tailscale0 and lo (iptables + ip6tables TS-ONLY chain), at every boot.
#   Ollama     ollama-override.conf makes Ollama listen on 0.0.0.0 and refuse to start
#              unless tailscale-only.service is active.
#   NodePorts  k3s kube-proxy opens NodePorts only on Tailscale addresses
#              and localhost (k3s-config.yaml -> /etc/rancher/k3s/config.yaml). Covers every NodePort
#              service, including ones added later.
#
# Why not netfilter-persistent: `netfilter-persistent save` snapshots every rule on the
# host, including k3s/Docker/Tailscale chains. At boot those chains don't exist yet, so
# the restore aborts and none of the rules load. This script disables it.
#
# BREAK-GLASS: if Tailscale is broken and you are at the machine:
#   sudo systemctl stop tailscale-only     (opens SSH and Ollama on every interface)
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }

if [ -f /etc/systemd/system/ssh-tailscale-only.service ]; then
  echo ">> Replacing ssh-tailscale-only.service with tailscale-only.service"
  systemctl disable --now ssh-tailscale-only.service
  rm /etc/systemd/system/ssh-tailscale-only.service
fi

echo ">> Host ports: installing tailscale-only.service"
install -m 644 "$HERE/tailscale-only.service" /etc/systemd/system/tailscale-only.service
systemctl daemon-reload
systemctl enable tailscale-only.service
systemctl restart tailscale-only.service

echo ">> Ollama: listen on all interfaces (firewalled to tailscale0)"
if systemctl list-unit-files ollama.service >/dev/null 2>&1; then
  install -D -m 644 "$HERE/ollama-override.conf" /etc/systemd/system/ollama.service.d/override.conf
  systemctl daemon-reload
  systemctl restart ollama
else
  echo "   ollama.service not installed, skipping"
fi

echo ">> NodePorts: k3s nodeport-addresses"
if cmp -s "$HERE/k3s-config.yaml" /etc/rancher/k3s/config.yaml; then
  echo "   already configured"
elif [ -f /etc/rancher/k3s/config.yaml ]; then
  echo "   /etc/rancher/k3s/config.yaml exists and differs; merge k3s-config.yaml into it by hand, then: systemctl restart k3s"
  exit 1
else
  install -D -m 644 "$HERE/k3s-config.yaml" /etc/rancher/k3s/config.yaml
  echo "   restarting k3s (running pods are not restarted)"
  systemctl restart k3s
fi

echo ">> Disabling netfilter-persistent (old full-host snapshot)"
if systemctl is-enabled -q netfilter-persistent 2>/dev/null; then
  systemctl disable netfilter-persistent
fi
for f in /etc/iptables/rules.v4 /etc/iptables/rules.v6; do
  if [ -f "$f" ]; then mv "$f" "$f.disabled-$(date +%F)"; fi
done
systemctl reset-failed netfilter-persistent 2>/dev/null || true

echo ">> Verify"
iptables -S TS-ONLY
ip6tables -S TS-ONLY
iptables -S INPUT | grep TS-ONLY
curl -s -m5 http://127.0.0.1:11434/api/version && echo
ss -ltn | grep ':11434 '
grep -r nodeport-addresses /etc/rancher/k3s/config.yaml
echo
echo ">> Undo:"
echo "   sudo rm /etc/systemd/system/ollama.service.d/override.conf && sudo systemctl daemon-reload && sudo systemctl restart ollama"
echo "   sudo systemctl disable --now tailscale-only && sudo rm /etc/systemd/system/tailscale-only.service"
echo "   sudo rm /etc/rancher/k3s/config.yaml && sudo systemctl restart k3s"
