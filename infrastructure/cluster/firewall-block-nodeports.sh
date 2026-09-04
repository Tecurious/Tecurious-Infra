#!/usr/bin/env bash
# LAN firewall block for k8s NodePorts — Tailscale-only access.
# Applied rule + persistence. Run once per host; idempotent.
#
# Ports covered:
#   22    - SSH (sshd still listens on all IFs; blocked except tailscale0)
#   31322 - argocd-server HTTP NodePort
#   30909 - argocd-server HTTPS NodePort
#   30300 - postgres-mcp NodePort
#
# Effect: these ports are reachable ONLY via tailscale0 interface.
# Direct LAN/public access is dropped.
#
# BREAK-GLASS: if Tailscale is broken and you are home, delete the SSH rule:
#   sudo iptables -D INPUT ! -i tailscale0 -p tcp --dport 22 -j DROP
set -euo pipefail

PORTS="31322,30909,30300"
SSH_PORT="22"
RULE="! -i tailscale0 -p tcp -m multiport --dports ${PORTS} -j DROP"
SSH_RULE="! -i tailscale0 -p tcp --dport ${SSH_PORT} -j DROP"

echo ">> Checking for existing rule..."
if iptables -C INPUT $(echo "$RULE" | sed 's/! -i/! -i/') 2>/dev/null; then
  echo "   rule already present, nothing to do"
else
  echo ">> Inserting iptables rule..."
  iptables -I INPUT $RULE
fi

echo ">> Checking SSH rule (port ${SSH_PORT})..."
if iptables -C INPUT $(echo "$SSH_RULE" | sed 's/! -i/! -i/') 2>/dev/null; then
  echo "   SSH rule already present, nothing to do"
else
  echo ">> Inserting SSH iptables rule..."
  iptables -I INPUT $SSH_RULE
fi

echo ">> Making persistent across reboots..."
# netfilter-persistent is the standard Ubuntu 24.04 mechanism
if ! command -v netfilter-persistent >/dev/null 2>&1; then
  echo "   installing iptables-persistent (DEBIAN_FRONTEND=noninteractive)"
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q iptables-persistent
fi
netfilter-persistent save

echo ">> Verify:"
iptables -L INPUT -n --line-numbers | grep -E "dports|dport ${SSH_PORT}|DROP" | head -5
echo
echo ">> NOTE: to undo manually:"
echo "   NodePorts: iptables -D INPUT -p tcp -m multiport --dports ${PORTS} -j DROP"
echo "   SSH:       iptables -D INPUT ! -i tailscale0 -p tcp --dport ${SSH_PORT} -j DROP"
