# Remote Desktop (saiserver)

How this homelab copies the Ubuntu desktop to the Mac.

**Read in this order:**

1. [concepts.md](concepts.md) — what X11, Wayland, VNC, x11vnc, bind addresses, and `ssh -N -L` *are* (no machine-specific addresses)
2. **This page** — the commands we actually use, with each flag explained
3. [setup.md](setup.md) — files on disk, systemd, GDM, troubleshooting

---

## What is running today

| Piece | On saiserver |
|---|---|
| Display | Xorg `:0` (GDM `WaylandEnable=false`, autologin `vallaksa`) |
| VNC | `x11vnc` via user systemd, password file `~/.vnc/passwd` |
| Listen | Tailscale IPv4 from `tailscale ip -4`, port **5900** |
| Mac | Screen Sharing → that IPv4, no SSH tunnel |

GUI programs stay on the server. The Mac only views them.

Do not commit live Tailscale IPs, MagicDNS names, or VNC passwords. Look them up with `tailscale ip -4` / `tailscale status`.

---

## Daily: open the desktop from the Mac

Wait until GNOME has finished autologin after a reboot.

On the **server**, copy the IPv4:

```bash
tailscale ip -4
```

On the **Mac**, substitute that address (do not commit the real value):

```bash
open vnc://<server-tailscale-ipv4>:5900
```

| Part | Meaning |
|---|---|
| `open` | macOS: open this URL with the default app (Screen Sharing) |
| `vnc://` | Use the VNC protocol (Screen Sharing is a VNC client) |
| `<server-tailscale-ipv4>` | Output of `tailscale ip -4` on the server |
| `5900` | Port x11vnc listens on |

Password is the **VNC** password in `~/.vnc/passwd` on the server, not the Linux login password. Save it in Keychain and add the URL to Screen Sharing favorites.

You do **not** run `ssh -N -L` for this path. VNC is already reachable on the tailnet.

---

## Commands we used (and what each one did)

These are the commands from the setup, in the order they matter. Conceptual background is in [concepts.md](concepts.md).

### On the server — is the desktop X11?

```bash
loginctl show-session 2 -p Type --value
```

Prints `x11` or `wayland`. x11vnc only works when this is `x11`. Session id `2` is typical for the graphical seat; `loginctl list-sessions` lists them if `2` is wrong.

```bash
ls -l /tmp/.X11-unix/
```

X11 display `:0` appears as socket `X0`. Missing `X0` means there is no X11 display `:0`.

### On the server — force Xorg at autologin (needed sudo, once)

```bash
sudo sed -i 's/^#WaylandEnable=false/WaylandEnable=false/' /etc/gdm3/custom.conf
sudo reboot
```

Ubuntu 24.04 autologin was starting **Wayland**. x11vnc then exited 78. Uncommenting `WaylandEnable=false` makes GDM start **Xorg**. Reboot applies it. Run this **on saiserver**, not on the Mac.

### On the server — VNC password file

```bash
mkdir -p ~/.vnc
x11vnc -storepasswd ~/.vnc/passwd
```

Writes a VNC-only password (not your user password). Screen Sharing always sends a password; without this file (or with `-nopw`) the Mac dialog sits on “Connecting…”.

### On the server — daemon status

```bash
systemctl --user status x11vnc
systemctl --user is-active x11vnc
systemctl --user restart x11vnc
journalctl --user -u x11vnc -e
```

`systemctl --user` talks to **your** systemd, not the machine-wide one. `x11vnc` here is the unit in `~/.config/systemd/user/x11vnc.service`. It starts after graphical login.

Exit **78** in the log means the wrapper saw Wayland and refused to start (on purpose).

```bash
ss -lntp | grep 5900
tailscale ip -4
```

You want a listen line on `<server-tailscale-ipv4>:5900` owned by `x11vnc`, matching `tailscale ip -4`.

### On the Mac — daily connect (current setup)

```bash
open vnc://<server-tailscale-ipv4>:5900
```

See the table above. Requires x11vnc already listening on the Tailscale IP.

---

## Older path: SSH local forward (do not use daily)

We used this while x11vnc listened only on **localhost**. Screen Sharing cannot reach `127.0.0.1` on another computer, so SSH forwarded a Mac port into the server’s loopback.

### 1. Open the SSH session (Mac Terminal — leave it running)

```bash
ssh -N -L 15900:127.0.0.1:5900 vallaksa@<server-tailscale-ipv4>
```

| Piece | What it does |
|---|---|
| `ssh` | Encrypted client. First it connects to **port 22** on `<server-tailscale-ipv4>`, then logs in as `vallaksa`. |
| `vallaksa@<server-tailscale-ipv4>` | Account `@` host. `USER@…` failed because `USER` is not an account. |
| `-N` | After login, **do not** start `bash` on the server. Keep the SSH process alive with no shell. The terminal looks frozen; that is expected. Ctrl+C ends the forward. |
| `-L` | **Local forward.** See the next table. |

**`-L 15900:127.0.0.1:5900` is three fields:**

| Field | Value | Where it lives | When it is used |
|---|---|---|---|
| Local port | `15900` | **Mac** | As soon as `ssh` succeeds, SSH **listens** on the Mac at `127.0.0.1:15900`. Nothing has used VNC yet. |
| Destination host | `127.0.0.1` | **Server** (not the Mac) | Used **later**, when something hits 15900. SSH on the server dials loopback. |
| Destination port | `5900` | **Server** | x11vnc’s port, if it is listening on localhost. |

Sequence:

1. You run the `ssh` line → Mac talks to **saiserver:22** only. VNC is idle.
2. SSH is up → Mac now has a listener on **15900**. Still no VNC.
3. You open Screen Sharing to `127.0.0.1:15900` → that hits the Mac listener.
4. SSH then, **on the server**, connects to **the server’s** `127.0.0.1:5900`.
5. If x11vnc is there, pixels flow. If not: `channel 2: open failed: connect failed: Connection refused`.

Why `15900` not `5900` on the Mac: macOS already binds **5900** (`Address already in use`). The left port is only a local spare. It is not x11vnc’s port.

### 2. Open the viewer (second Mac Terminal, while SSH is still running)

```bash
open vnc://127.0.0.1:15900
```

| Part | Meaning |
|---|---|
| `127.0.0.1` | The Mac itself, because that is where SSH is listening |
| `15900` | The local port from `-L` |

Screen Sharing never dials `<server-tailscale-ipv4>:5900` on this path. It dials the Mac; SSH carries the bytes.

This path **fails** with the current daemon, because x11vnc now listens on the Tailscale IPv4, not `127.0.0.1:5900`. Step 4 above would get connection refused. Daily use is `open vnc://<server-tailscale-ipv4>:5900` instead.

---

## After a reboot

1. Wait for autologin / GNOME on saiserver.
2. On the Mac: `open vnc://<server-tailscale-ipv4>:5900`.

---

## Related

- [concepts.md](concepts.md) — X11, Wayland, VNC, x11vnc, bind, SSH `-N`/`-L`
- [setup.md](setup.md) — unit file, GDM, password, discarded options
- [Tailscale Networking](../tailscale-networking.md)
