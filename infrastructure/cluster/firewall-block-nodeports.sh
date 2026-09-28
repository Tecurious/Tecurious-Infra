#!/usr/bin/env bash
# Tailscale-only access for SSH and k8s NodePorts. Run once per host with sudo; idempotent.
#
#   SSH (22)   ssh-tailscale-only.service adds an iptables + ip6tables INPUT DROP for
#              port 22 on every interface except tailscale0, at every boot.
#   NodePorts  k3s kube-proxy opens NodePorts only on Tailscale addresses
#              and localhost (k3s-config.yaml -> /etc/rancher/k3s/config.yaml). Covers every NodePort
#              service, including ones added later.
#
# Why not netfilter-persistent: `netfilter-persistent save` snapshots every rule on the
# host, including k3s/Docker/Tailscale chains. At boot those chains don't exist yet, so
# the restore aborts and none of the rules load. This script disables it.
#
# BREAK-GLASS: if Tailscale is broken and you are at the machine:
#   sudo systemctl stop ssh-tailscale-only
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }

echo ">> SSH: installing ssh-tailscale-only.service"
install -m 644 "$HERE/ssh-tailscale-only.service" /etc/systemd/system/ssh-tailscale-only.service
systemctl daemon-reload
systemctl enable --now ssh-tailscale-only.service

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
iptables -S INPUT | grep -- '--dport 22'
ip6tables -S INPUT | grep -- '--dport 22'
grep -r nodeport-addresses /etc/rancher/k3s/config.yaml
echo
echo ">> Undo:"
echo "   sudo systemctl disable --now ssh-tailscale-only && sudo rm /etc/systemd/system/ssh-tailscale-only.service"
echo "   sudo rm /etc/rancher/k3s/config.yaml && sudo systemctl restart k3s"
