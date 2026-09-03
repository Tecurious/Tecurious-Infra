# Remote Desktop — Concepts

This file explains the ideas only. No hostnames, no Tailscale addresses, no “how we wired saiserver.”

For the actual commands on this homelab, read [README.md](README.md) next. For files on disk, read [setup.md](setup.md).

Read in order. Each section is one idea.

---

## What problem exists

A graphical program (a window, a desktop, a browser) does not draw on the monitor by itself. It talks to a **display server**: software that owns the screen, the mouse, and the keyboard.

A normal `ssh` login does **not** give you that. SSH gives you a text shell. The display server, if it is running, is a separate program on the same computer.

Remote desktop means: copy that screen to another computer, and send mouse/keyboard back.

Three layers are involved:

1. **Display server** — owns the screen on the machine that runs the GUI (X11 or Wayland).
2. **Remote-desktop protocol** — copies pixels over the network (VNC is one such protocol).
3. **How the client reaches that protocol** — a VPN address, or an SSH port forward.

---

## X11

**X11** is a display protocol. It has been the usual way Linux programs draw windows for decades.

The program that implements X11 on the machine is often called **Xorg**. People say “X11” for the protocol and “Xorg” for the process.

Properties that matter here:

- There is one shared screen, named **`:0`** for the first local display, `:1` for the second, and so on.
- GUI programs set an environment variable `DISPLAY=:0` (or `:1`, …) so they know which screen to use.
- Any program that is allowed to talk to that display can read the whole screen (screenshot, remote desktop, accessibility tools). That is how `x11vnc` works: it asks X11 for the pixels of `:0`.

X11 does not copy the screen to another computer. It only runs the desktop **on that computer**.

---

## Wayland

**Wayland** is a newer display protocol. Ubuntu 24.04 uses it by default.

The window manager (on Ubuntu, GNOME Shell) *is* the display server. There is no separate “Xorg owns the whole screen, anyone with permission may read it” model.

Consequences:

- A random program cannot ask for “the entire desktop bitmap” the way it can on X11.
- Tools written only for X11 (including **x11vnc**) do not work as a full-desktop copy on a Wayland session.
- Ubuntu still ships **Xwayland**: a small X11 adapter so old X11 apps can open windows on a Wayland desktop. That adapter is not a full X11 desktop. x11vnc attaching to it fails when it tries to read the whole screen.

X11 vs Wayland is a choice of **display server**, not a VNC setting. If you need x11vnc, the login session must be X11 (on Ubuntu the session name is **Ubuntu on Xorg**).

---

## Display `:0`

`:0` is just the name of the first local X11 display. It usually means the built-in laptop screen.

- `DISPLAY=:0 some-gui-app` — start that app on that screen, even if you typed the command over SSH.
- Linux exposes it as a socket file, typically `/tmp/.X11-unix/X0`. If that socket is missing, there is no X11 display `:0` right now.

Wayland sessions may still create Xwayland sockets. Presence of a socket is not enough; the session type must actually be X11 for x11vnc to copy the desktop.

---

## VNC

**VNC** (Virtual Network Computing) is a protocol whose job is: send a rectangle of pixels to a client, and receive mouse and keyboard events.

- Default TCP port: **5900**.
- Client examples: macOS **Screen Sharing**, TigerVNC, RealVNC.
- It is not SSH. It is not a web page. It is not RDP (Remote Desktop Protocol, usually port 3389; that is what Windows and some GNOME “Remote Desktop” settings use).

macOS Screen Sharing **is** a VNC client. It always sends a password during connect. The VNC server has its own password, separate from the Linux user password.

VNC does not start your desktop. Something else must already be drawing a desktop. VNC only **exports** that picture.

---

## x11vnc

**x11vnc** is a VNC *server* that attaches to an **existing X11** display.

It does not create a second desktop. It reads `:0` (or whichever `DISPLAY` you give it) and speaks VNC on a TCP port (usually 5900).

That is why the name is `x11` + `vnc`: X11 on one side, VNC on the other.

If the session is Wayland, x11vnc has no full X11 desktop to read, and it fails.

---

## Bind address: who is allowed to connect

A server program **listens** on an IP + port.

| Listen address | Who can connect |
|---|---|
| `127.0.0.1:5900` | Only programs **on the same computer**. Other machines cannot reach it, even on the same VPN. |
| A VPN interface IP, e.g. the machine’s Tailscale IPv4, port 5900 | Any peer on that VPN that can reach that IP. Not the public internet, if you did not bind the public NIC. |
| `0.0.0.0:5900` | Every network interface, including LAN and often the public NIC. Avoid this unless you intend it. |

If VNC listens only on `127.0.0.1`, a Mac cannot connect to `vnc://<server-vpn-ip>:5900`. Something **on the server** must accept the connection to 5900. That is what an SSH local forward does: the SSH **server** process connects to `127.0.0.1:5900` for you.

If VNC already listens on the VPN IP, the Mac can open Screen Sharing straight at that IP and port. No forward.

---

## SSH: login vs local forward (`-N` and `-L`)

SSH always starts the same way: the **client** (your Mac) opens a TCP connection to the **SSH daemon** on the remote machine, normally **port 22**. After keys or a password succeed, you have an encrypted session.

That session can do two different jobs. They are easy to mix up.

### Job A — a remote shell (the default)

```bash
ssh user@server
```

SSH starts `bash` (or your login shell) **on the server**. You type commands there. When you exit, the SSH connection ends.

### Job B — hold the session, do not start a shell (`-N`)

```bash
ssh -N user@server
```

`-N` means: authenticate, keep the encrypted session **open**, and **do not** run a remote shell.

The terminal looks “stuck.” That is the session sitting idle on purpose. Ctrl+C closes it.

Use `-N` when the only reason for SSH is forwarding ports, not running `ls` or `htop`.

### Job C — local forward (`-L`), which uses that session

```bash
ssh -N -L 15900:127.0.0.1:5900 user@server
```

Parse `-L` as **three** pieces, not two:

```text
-L  LOCAL_PORT  :  DESTINATION_HOST  :  DESTINATION_PORT
         │                  │                    │
         │                  └────────┬───────────┘
         │                           │
         │         used on the SERVER after SSH is already connected
         │
    used on YOUR machine (the SSH client)
```

**When you press Enter on this command, two things happen, and one thing does not.**

1. **Does happen:** Mac SSH client connects to `server:22`, logs in as `user`. Same as a normal SSH login.
2. **Does happen:** SSH client starts **listening on the Mac** on `LOCAL_PORT` (here `15900`), on localhost.
3. **Does not happen yet:** nobody has talked to VNC. Port `5900` on the server has not been touched. Screen Sharing has not started.

The SSH process is now a **waiting relay**.

**When you later open Screen Sharing to `127.0.0.1:15900`:**

1. Screen Sharing connects to **the Mac**, port 15900. It thinks VNC is local.
2. The SSH **client** accepts that connection.
3. Inside the **existing** SSH session, SSH opens an extra channel.
4. The SSH **daemon on the server** then opens a **new** TCP connection from the server to `DESTINATION_HOST:DESTINATION_PORT`.
5. In the command above that target is `127.0.0.1:5900` **on the server** — x11vnc, if it is listening on loopback.
6. Bytes flow: Screen Sharing ↔ Mac:15900 ↔ SSH tunnel ↔ server’s 127.0.0.1:5900 ↔ x11vnc ↔ X11.

`127.0.0.1` in `-L …:127.0.0.1:5900` is **not** the Mac. After SSH has logged into the server, “localhost” means the server.

**Why 15900 and not 5900 on the Mac?** The left number is only a local door. It can be any free port. macOS often already uses 5900 for its own Screen Sharing server, so 15900 is a free spare. The VNC server’s port stays 5900 **on the machine where x11vnc runs**.

**Failure that matches this model:** SSH prints `channel … open failed: connect failed: Connection refused`. Meaning: step 1–3 worked (SSH is up, Mac:15900 accepted Screen Sharing). Step 4–5 failed: on the server, nothing was listening on `127.0.0.1:5900`.

---

## systemd (only what you need)

**system** services (`sshd`) start at boot as root.

A **user** service starts after that user has a session. If it is tied to `graphical-session.target`, it starts when the graphical desktop is up, not at the text login screen.

That is why x11vnc as a user service is not the same as “always on from power-on.” It needs an X11 graphical login first.

---

## Glossary

| Term | Meaning |
|---|---|
| **Display server** | Program that owns screen, mouse, keyboard for GUI apps |
| **X11** | Old Linux display protocol |
| **Xorg** | Common program that implements X11 |
| **Wayland** | Newer display protocol; GNOME Shell is the server |
| **Xwayland** | X11 compatibility on top of Wayland; not a full desktop for x11vnc |
| **`:0`** | First local X11 display |
| **VNC / RFB** | Protocol to send a screen over TCP (typical port 5900) |
| **x11vnc** | VNC server attached to an existing X11 display |
| **RDP** | Different remote-desktop protocol (typical port 3389) |
| **Bind / listen** | IP+port a server accepts connections on |
| **`127.0.0.1`** | Loopback: only the same computer |
| **SSH `-N`** | Keep SSH up; do not start a remote shell |
| **SSH `-L`** | Listen on the client; when someone connects, the *server* dials host:port |
