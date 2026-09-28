# Terminal Cheat Sheet

Commands for checking on and finding your way around saiserver. Replace anything in `<angle brackets>` with a real value.

Start with [First look](#first-look) when something seems wrong.

---

## First look

Run these first when something seems off.

```bash
uptime                                   # time since boot + load (compare load to CPU count: nproc)
systemctl --failed                       # failed system services
systemctl --user --failed                # failed user services (x11vnc)
journalctl -b -p err --no-pager | tail -50   # errors since this boot
df -h /                                  # disk space
free -h                                  # memory
kubectl get pods -A | grep -v Running    # unhealthy pods
docker ps -a --filter status=exited      # stopped/crashed containers
```

---

## Getting in

```bash
ssh vallaksa@<server-tailscale-ipv4>     # from anywhere on the tailnet
ssh vallaksa@<server-lan-ip>             # from home
open vnc://<server-tailscale-ipv4>:5900  # Mac: desktop via Screen Sharing (see remote-desktop/)
```

Keep long jobs alive after you disconnect with **tmux**:

```bash
tmux new -s work                         # new session named "work"
tmux ls                                  # list sessions
tmux attach -t work                      # reattach
# inside tmux: Ctrl+b d = detach · Ctrl+b c = new window · Ctrl+b n / p = next / previous window
```

---

## Services (systemd)

```bash
systemctl status <name>                  # running? + last log lines
systemctl start|stop|restart <name>
systemctl enable --now <name>            # start now and at every boot
systemctl disable --now <name>           # stop now and never at boot
systemctl cat <name>                     # show the unit file
sudo systemctl edit --full <name>        # edit the unit file
sudo systemctl daemon-reload             # after editing unit files by hand
systemctl show <name> -p NRestarts       # restart count: a high number means it's crash-looping
```

Counting and listing:

```bash
systemctl list-units --type=service --state=running --no-legend | wc -l   # how many running
systemctl list-units --type=service --state=running                       # list them
systemctl list-units --type=service --state=failed                        # failed ones
systemctl list-unit-files --type=service --state=enabled                  # set to start at boot
```

Add `--user` to any of these for your own services (for example `systemctl --user status x11vnc`). User unit files live in `~/.config/systemd/user/`; system ones in `/etc/systemd/system/`.

---

## Logs (journalctl)

```bash
journalctl -u <name> -f                  # follow a service live (Ctrl+C to stop)
journalctl -u <name> -b --no-pager | tail -50   # since this boot
journalctl -u <name> --since "-30min"    # last 30 minutes
journalctl -b -p warning                 # warnings and worse, this boot
journalctl -k -b                         # kernel messages (drivers, hardware)
journalctl --list-boots | tail           # past boots
journalctl -b -1 -p err                  # errors from the previous boot (after a crash)
journalctl --disk-usage                  # how much space logs take
sudo journalctl --vacuum-time=14d        # delete logs older than 14 days
```

---

## CPU, memory and processes

```bash
htop                                     # live view (F6 sort, F9 kill, q quit)
ps aux --sort=-%mem | head               # top memory users
ps aux --sort=-%cpu | head               # top CPU users
pgrep -a <name>                          # find processes by name, with their command lines
kill <pid>                               # ask a process to stop
kill -9 <pid>                            # force it
ps -eo pid,ppid,stat,etime,cmd | grep '[n]ame'   # state, parent and age of a process
```

In `ps` output, `STAT` `Z` means zombie (dead but not cleaned up) and `D` means stuck waiting on the disk or a driver.

---

## Disk

```bash
df -h                                    # free space per filesystem
sudo du -xh --max-depth=1 / | sort -h    # biggest top-level folders
du -sh ~/* | sort -h                     # biggest things in your home
find / -xdev -size +1G 2>/dev/null       # files over 1 GB
docker system df                         # space used by Docker
lsblk                                    # disks and partitions
```

---

## Network and ports

```bash
ip -br addr                              # IPs per interface (enp2s0 = LAN, tailscale0 = tailnet)
ss -ltnp                                 # everything listening: port + program
ss -ltnp | grep :<port>                  # who holds a specific port
curl -sI localhost:<port>                # does a web service answer?
ping -c3 1.1.1.1                         # internet reachable?
resolvectl query <hostname>              # DNS lookup
```

A service bound to `127.0.0.1` is only reachable from the server itself; `0.0.0.0` or `[::]` means every interface, including public IPv6.

### Tailscale

```bash
tailscale status                         # devices on the tailnet and whether they're online
tailscale ip -4                          # this server's tailnet IPv4
tailscale ping <device>                  # test the path to another device
tailscale serve status                   # what's shared via tailscale serve
```

See [tailscale-networking.md](tailscale-networking.md).

### Firewall

```bash
sudo iptables -S INPUT                   # IPv4 rules, top to bottom
sudo ip6tables -S INPUT                  # IPv6 rules
systemctl status tailscale-only          # adds the Tailscale-only rule for SSH + Ollama at boot
```

See [firewall.md](firewall.md).

---

## Docker

```bash
docker ps                                # running containers
docker ps -a                             # all, including stopped
docker logs -f --tail 100 <container>    # follow logs
docker stats --no-stream                 # CPU/memory per container
docker exec -it <container> sh           # shell inside a container
docker restart <container>
docker inspect <container> | less        # full config (mounts, env, network)
docker network ls                        # networks
docker system prune                      # remove stopped containers, unused networks, dangling images
```

Infra containers are defined in `/opt/docker-infra/docker-compose.yml`:

```bash
cd /opt/docker-infra
docker compose ps
docker compose logs -f <service>
docker compose up -d                     # apply changes to the compose file
docker compose pull && docker compose up -d   # update images
```

See [docker-networking.md](docker-networking.md) and [directory-layout.md](directory-layout.md).

---

## Kubernetes (k3s)

`kubectl` is k3s's kubectl and works without sudo.

```bash
kubectl get nodes
kubectl get pods -A                      # every pod in every namespace
kubectl get pods -A | grep -v Running    # only the unhealthy ones
kubectl get all -n <ns>                  # everything in one namespace
kubectl describe pod <pod> -n <ns>       # why it's stuck: read Events at the bottom
kubectl logs <pod> -n <ns> --tail 100
kubectl logs <pod> -n <ns> --previous    # logs from before the last crash
kubectl logs -f deploy/<name> -n <ns>    # follow a deployment's logs
kubectl get events -A --sort-by=.lastTimestamp | tail -20
kubectl rollout restart deploy/<name> -n <ns>
kubectl exec -it <pod> -n <ns> -- sh     # shell inside a pod
kubectl port-forward svc/<svc> -n <ns> 8080:80   # reach a service on localhost:8080
```

Namespaces in use: `cloudflared`, `data`, `dev`, `devpool` (ArgoCD), `devstrom`.

### ArgoCD

```bash
kubectl -n devpool get applications      # sync + health for every app
kubectl -n devpool describe application <app>   # why an app is Degraded or OutOfSync
```

See [adding-a-service.md](adding-a-service.md).

---

## GPU and Ollama

```bash
nvidia-smi                               # GPU use, memory, processes
watch -n1 nvidia-smi                     # live view
ollama list                              # models
ollama ps                                # models loaded right now
ollama run <model>                       # chat in the terminal
systemctl status ollama                  # system service, runs as user "ollama"
journalctl -u ollama -f
```

- Ollama runs as one **system** service from `/usr/local/bin/ollama`; data and sign-in key are in `/usr/share/ollama/.ollama`. It listens on port 11434, reachable from the server and over Tailscale only.
- From a Mac on the tailnet: `OLLAMA_HOST=http://sai:11434 ollama list`
- `nvidia-smi` saying `Driver/library version mismatch` means the driver was updated and the old one is still loaded. Reboot.

---

## Desktop and remote screen

```bash
loginctl list-sessions                   # graphical session present? (seat0)
ps -eo pid,ppid,stat,cmd | grep '[X]org' # Xorg state: <defunct> means frozen
systemctl --user status x11vnc
ss -ltnp | grep 5900                     # VNC listening?
tail -30 ~/.local/share/xorg/Xorg.0.log  # Xorg log
```

Frozen Xorg: `kill -9 <xorg-pid> <gdm-x-session-pid>` and GDM logs you back in. See [remote-desktop/](remote-desktop/README.md) and [remote-desktop/display-freeze.md](remote-desktop/display-freeze.md).

---

## Hardware and power

```bash
sensors                                  # temperatures (sudo apt install lm-sensors)
cat /sys/class/power_supply/BAT0/capacity    # battery %
cat /sys/class/power_supply/BAT0/status      # Charging / Full / Discharging
lspci | grep -iE 'vga|3d'                # GPUs
last -x reboot shutdown | head           # recent reboots
hostnamectl                              # OS, kernel, machine
```

---

## Packages and updates

```bash
sudo apt update                          # refresh package lists
apt list --upgradable                    # what would update
sudo apt upgrade                         # install updates
apt policy <package>                     # installed vs available version
dpkg -l | grep <word>                    # installed packages matching a word
sudo apt autoremove                      # remove packages nothing needs
[ -f /var/run/reboot-required ] && echo "reboot needed"
```

---

## Files and text

```bash
ls -lah                                  # list with sizes and hidden files
tree -L 2                                # folder tree, 2 levels
less <file>                              # read a file (/ search, q quit)
tail -f <file>                           # follow a growing file
grep -rn "<text>" <dir>                  # search inside files
find <dir> -name "*.yaml"                # find files by name
nano <file>                              # simple editor (Ctrl+O save, Ctrl+X exit)
sudo chown <user>:<group> <file>         # change owner
chmod 600 <file>                         # owner-only read/write (keys, .env)
```

---

## Shell shortcuts

```bash
sudo !!                                  # rerun the last command with sudo
!$                                       # last argument of the previous command
cd -                                     # back to the previous folder
history | grep <word>                    # find an old command
```

| Keys | Does |
|---|---|
| `Ctrl+R` | Search command history as you type |
| `Ctrl+C` | Stop the running command |
| `Ctrl+L` | Clear the screen |
| `Ctrl+A` / `Ctrl+E` | Jump to start / end of the line |
| `Ctrl+U` | Delete from the cursor back to the start |
| `Tab` | Autocomplete |

---

## Power

```bash
sudo reboot
sudo shutdown -h now                     # power off
sudo shutdown -r +5                      # reboot in 5 minutes
sudo shutdown -c                         # cancel a scheduled shutdown
```

Sleep, suspend and hibernate are disabled (masked) on this server, so closing the lid is safe.
