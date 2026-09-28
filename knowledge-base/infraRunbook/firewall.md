# Firewall

How saiserver decides who can connect to what. There are three layers: the home router, Tailscale, and the server's own firewall.

Setup lives in [`infrastructure/cluster/`](../../infrastructure/cluster/): `firewall-block-nodeports.sh` installs everything below.

---

## Layer 1: the home router (front gate)

```
Internet ──X──> [ home router ] ───> home Wi-Fi / LAN ───> saiserver
```

- **IPv4:** the router blocks all incoming connections from the internet by default. Nobody outside can start a connection to the server over IPv4.
- **IPv6:** the server also has public IPv6 addresses (`2600:…`). Whether the router blocks incoming IPv6 depends on its settings. Most block it by default, but don't rely on the router alone.

## Layer 2: Tailscale (private tunnel)

```
Your Mac ══════ encrypted Tailscale tunnel ══════> saiserver
 (anywhere)                                        arrives on "tailscale0"
```

- Tailscale builds a private network between your own devices, wherever they are.
- Traffic that comes through it arrives on the network interface **`tailscale0`**.
- Only devices signed in to the tailnet can use it.

See [tailscale-networking.md](tailscale-networking.md).

## Layer 3: the server's own firewall (bouncer)

Every connection arrives through one of the server's network interfaces:

| Interface | What it is |
|---|---|
| `wlp4s0` | Home Wi-Fi |
| `enp2s0` | Ethernet cable |
| `tailscale0` | Tailscale tunnel |
| `lo` | The server talking to itself (localhost) |

Linux checks incoming connections against **iptables** rules, top to bottom:

```
New connection arrives
        │
        ▼
 Kubernetes & Tailscale housekeeping rules (added automatically)
        │
        ▼
 Is it for port 22 (SSH) or 11434 (Ollama)?  ──yes──> TS-ONLY chain:
        │ no                                     from lo (the server itself)?  → allow
        │                                        from tailscale0?              → allow
        │                                        anything else                 → DROP (timeout)
        │ no
        ▼
 ACCEPT (default: allow)
```

The `TS-ONLY` chain comes from **`tailscale-only.service`**. It rebuilds the chain at every boot, for IPv4 and IPv6. `lo` must be allowed, or programs on the server itself can't reach Ollama on `127.0.0.1:11434`. To protect another host port, add it to `PORTS` in [`tailscale-only.service`](../../infrastructure/cluster/tailscale-only.service) and re-run the script.

**Kubernetes NodePorts** (ArgoCD, postgres-mcp, 9router) are handled differently. k3s is configured (`/etc/rancher/k3s/config.yaml`) to open NodePorts only on Tailscale addresses (`100.64.0.0/10`) and localhost. A `DROP` rule in `INPUT` can't do this job, because kube-proxy redirects NodePort traffic in `PREROUTING`, before `INPUT` ever sees it. Localhost is kept because `tailscale serve` proxies to `127.0.0.1:30300` and `127.0.0.1:31322`.

---

## Who can reach what

| Service | From Tailscale | From home Wi-Fi / LAN | From the internet |
|---|---|---|---|
| SSH (22) | ✅ | 🔒 dropped by firewall | 🔒 router + firewall |
| ArgoCD / postgres-mcp / 9router (NodePorts) | ✅ | 🔒 k3s only listens on Tailscale + localhost | 🔒 |
| CasaOS (80) | ✅ | ✅ open on purpose (photo/drive browsing at home) | 🔒 router (IPv4) |
| Ollama (11434) | ✅ `http://sai:11434` | 🔒 dropped by firewall | 🔒 router + firewall |
| Public apps via Cloudflare tunnel | No inbound port at all | | |

**Cloudflare tunnel:** `cloudflared` connects *outwards* to Cloudflare and keeps that connection open, and visitors' requests travel back along it. Nothing on the server waits for connections from the internet.

---

## Check it yourself

```bash
sudo iptables -S INPUT                 # IPv4 rules, top to bottom
sudo iptables -S TS-ONLY               # the Tailscale-only chain
sudo ip6tables -S INPUT                # IPv6 rules
systemctl status tailscale-only        # the SSH + Ollama rule service
cat /etc/rancher/k3s/config.yaml       # NodePort address limits
ss -ltnp                               # what's listening, and on which address
```

Reading `ss` output:

| Listen address | Who can connect |
|---|---|
| `127.0.0.1:<port>` | Only the server itself |
| `100.x.x.x:<port>` | Only Tailscale |
| `0.0.0.0:<port>`, `*:<port>`, `[::]:<port>` | Any network (then the firewall decides) |

Testing from another machine on the home network (not through Tailscale):

```bash
nc -vz -w3 <server-lan-ip> 22          # should time out
```

Use the server's *current* LAN IP (`ip -4 -br addr`). It moves between `enp2s0` and `wlp4s0` depending on whether the cable is plugged in, and DHCP can change it. Testing an address nobody holds also times out, which proves nothing.

---

## History: why not netfilter-persistent

The first version of the script saved rules with `netfilter-persistent save`. That snapshots **every** rule on the host, including k3s, Docker and Tailscale chains. At boot those chains don't exist yet, so `iptables-restore` aborted (`Set KUBE-SRC-… doesn't exist`) and none of the rules loaded, including the SSH block. The script now disables `netfilter-persistent` and keeps the old snapshot as `/etc/iptables/rules.v4/v6.disabled-<date>`.

---

## Break-glass

Tailscale down and you're at the machine:

```bash
sudo systemctl stop tailscale-only           # SSH and Ollama open on every interface
sudo systemctl start tailscale-only          # close them again afterwards
```

Undo everything:

```bash
sudo rm /etc/systemd/system/ollama.service.d/override.conf && sudo systemctl daemon-reload && sudo systemctl restart ollama
sudo systemctl disable --now tailscale-only && sudo rm /etc/systemd/system/tailscale-only.service
sudo rm /etc/rancher/k3s/config.yaml && sudo systemctl restart k3s
```

---

## Ollama over Tailscale

Ollama listens on `0.0.0.0:11434` ([`ollama-override.conf`](../../infrastructure/cluster/ollama-override.conf)) and `tailscale-only.service` drops 11434 on every interface except `tailscale0` and `lo`. The override also makes Ollama refuse to start unless that firewall service is active, so it can't come up unprotected.

From any tailnet device:

```bash
OLLAMA_HOST=http://sai:11434 ollama list
curl http://sai:11434/api/version
```

Ollama has no login, so anyone on the tailnet can use it, including the ollama.com cloud models signed in on the server.

**Why not `tailscale serve`:** while Ollama is bound to `127.0.0.1`, it rejects any request whose Host header isn't `localhost` with `403 Forbidden` (DNS-rebinding protection). `tailscale serve` passes the `sai.<tailnet>.ts.net` Host header through, so every request fails.
