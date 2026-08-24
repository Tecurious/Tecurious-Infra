# Remote Desktop — Our Setup

Concrete files and commands on **saiserver** (Ubuntu 24.04, user `vallaksa`). For *why*, see [concepts.md](concepts.md). For daily use, see [README.md](README.md).

---

## Inventory

| Item | Location / value |
|---|---|
| Host | `saiserver` |
| Tailscale IPv4 | `tailscale ip -4` on the server (do not commit the value) |
| Display | `:0` (Xorg, autologin as `vallaksa`) |
| VNC listen | `<server-tailscale-ipv4>:5900` |
| VNC password file | `~/.vnc/passwd` |
| Wrapper | `~/.local/bin/x11vnc-on-display` |
| User unit | `~/.config/systemd/user/x11vnc.service` |
| Log | `/tmp/x11vnc.log` |
| GDM | `/etc/gdm3/custom.conf` — `AutomaticLogin=vallaksa`, `WaylandEnable=false` |
| Session preference | AccountsService `XSession=ubuntu-xorg`; `~/.dmrc` |

HTTP services on this machine still bind `127.0.0.1` and use `tailscale serve`. VNC is the exception: it binds the Tailscale address so macOS Screen Sharing can dial it directly.

---

## systemd unit

`~/.config/systemd/user/x11vnc.service`:

- **Starts with** `graphical-session.target` (after GNOME is up), not at boot like `sshd`
- **Restarts** on crash (`Restart=on-failure`)
- **Does not loop** on Wayland: wrapper exits `78`, `RestartPreventExitStatus=78`
- **Linger** is already on for `vallaksa`, so the user systemd instance exists after login

```bash
systemctl --user status x11vnc
systemctl --user restart x11vnc
journalctl --user -u x11vnc -e
```

The wrapper refuses to start if:

- there is no X socket at `/tmp/.X11-unix/X0`
- seat0 session `Type` is `wayland`
- `~/.vnc/passwd` is missing
- `tailscale ip -4` is empty (will not bind `0.0.0.0`)

---

## GDM: force Xorg

Ubuntu 24.04 autologin prefers **Wayland** even if `XSession=ubuntu-xorg` is set. x11vnc then dies with `X_GetImage` / exit 78.

In `/etc/gdm3/custom.conf` under `[daemon]`:

```ini
AutomaticLoginEnable=True
AutomaticLogin=vallaksa
WaylandEnable=false
```

`WaylandEnable=false` must be **uncommented**. Then reboot once.

Confirm after login:

```bash
loginctl show-session 2 -p Type --value
# x11
```

### Wayland comes back

If someone logs in with the default “Ubuntu” (Wayland) session, or `WaylandEnable` is commented again:

```text
x11vnc: graphical session is Wayland; log into Ubuntu on Xorg.
```

Fix: restore `WaylandEnable=false`, reboot, or at GDM choose **Ubuntu on Xorg**.

---

## Password

VNC auth is **not** the Linux password.

```bash
mkdir -p ~/.vnc
x11vnc -storepasswd ~/.vnc/passwd   # prompts for a new VNC password
systemctl --user restart x11vnc
```

Never commit `~/.vnc/passwd`.

---

## What we tried and discarded

| Approach | Why it is not the daily path |
|---|---|
| `ssh -N -L 15900:127.0.0.1:5900` then `vnc://127.0.0.1:15900` | Works with `-localhost` bind. Extra terminal forever. Mac port 5900 is often taken (Screen Sharing). |
| Bind x11vnc `-localhost` only | Safe, but Screen Sharing cannot reach it without a tunnel. |
| GNOME Remote Desktop VNC (`gsettings`) | On this Ubuntu 46 build the user daemon brought up RDP objects only; nothing listened on 5900. |
| GNOME RDP | Needs TLS cert + Microsoft Remote Desktop on the Mac — not Screen Sharing. |
| X11 forwarding (`ssh -Y`) | `X11Forwarding no` in `sshd_config.d/99-custom.conf`. Electron/Chromium over X11 is a poor fit anyway. |

The SSH tunnel is still a valid **break-glass** tool if you temporarily bind x11vnc to `127.0.0.1` again. The command is explained field-by-field in [README.md](README.md#older-path-ssh-local-forward-do-not-use-daily). What `-N` and `-L` *mean* is in [concepts.md](concepts.md#ssh-login-vs-local-forward--n-and--l).

---

## Break-glass: tunnel (only if 5900 is localhost)

On Mac, if local 5900 is busy use 15900:

```bash
ssh -N -L 15900:127.0.0.1:5900 vallaksa@<server-tailscale-ipv4>
open vnc://127.0.0.1:15900
```

`-N` = no shell. Left port = Mac. Right `127.0.0.1:5900` = as seen **on the server**.

Current production bind is the Tailscale IP, so this tunnel to server-localhost will **connection refused** unless you change the wrapper back to `-localhost`. Full flag-by-flag explanation: [README.md](README.md#older-path-ssh-local-forward-do-not-use-daily).

---

## Useful commands

```bash
# Display server
loginctl list-sessions
ls -l /tmp/.X11-unix/

# Daemon
systemctl --user is-active x11vnc
ss -lntp | grep 5900
tail -50 /tmp/x11vnc.log

# Network
tailscale status
tailscale ip -4
```
