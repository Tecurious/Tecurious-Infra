# Display freeze with an HDMI monitor

Why saiserver's desktop froze when the ultrawide was plugged into HDMI, and how the full NVIDIA driver fixes it.

When Xorg (the desktop program) freezes, the monitor, the laptop screen and Screen Sharing from the Mac all stop working together.

---

## The laptop has two graphics chips

| Chip | Wired to | Driver before the fix |
|---|---|---|
| AMD Radeon Vega (built in) | Laptop's own screen (`eDP-1`) | `amdgpu`, full display support |
| NVIDIA GTX 1650 | **HDMI port** (`HDMI-A-1`) | `nvidia-headless-595-server`, compute only, **no display part** |

Anything plugged into HDMI can only be shown through the NVIDIA chip.

---

## Booting with the ultrawide plugged in (broken)

```
 SOFTWARE              INSIDE THE LAPTOP
                     +-----------------------------------------------------+
                     |                                                     |
+----------------+   |  +----------------+          +--------------------+ |
| Xorg (desktop) |----->| AMD chip       |--------->| Laptop screen      | |
| FROZEN ~30 s   |   |  | draws frames   |          | black              | |
+----------------+   |  +----------------+          +--------------------+ |
        |            |          |                                          |
        |            |          | copies every frame                       |
        |            |          | (workaround)  <-- this freezes Xorg      |
        |            |          v                                          |
        |            |  +----------------+          +--------------------+ |
        +-------------->| NVIDIA chip    |--------->| Ultrawide (HDMI)   | |
        |            |  | headless: no   |          | black              | |
        |            |  | display part   |          +--------------------+ |
        |            |  +----------------+                                 |
        |            +-----------------------------------------------------+
        v
+----------------+                               +--------------------+
| x11vnc         |  - - nothing on :5900 - - ->  | Mac Screen Sharing |
| never started  |                               | can't connect      |
+----------------+                               +--------------------+
```

1. Xorg sees the ultrawide on HDMI, which belongs to the NVIDIA chip.
2. The headless NVIDIA driver has no display part, so Xorg uses a workaround (reverse PRIME): AMD draws every frame and copies it to NVIDIA to send out.
3. About 30 seconds after boot, that workaround freezes Xorg. The last line in `~/.local/share/xorg/Xorg.0.log` each time was:
   ```
   randr: falling back to unsynchronized pixmap sharing
   ```
4. With no desktop, x11vnc never starts, so Screen Sharing on the Mac has nothing to connect to.

---

## Booting with the ultrawide unplugged (works)

```
 SOFTWARE              INSIDE THE LAPTOP
                     +-----------------------------------------------------+
+----------------+   |  +----------------+          +--------------------+ |
| Xorg (desktop) |----->| AMD chip       |--------->| Laptop screen      | |
| running        |   |  | draws desktop  |          | desktop shown      | |
+----------------+   |  +----------------+          +--------------------+ |
        |            |                                                     |
        |            |  +- - - - - - - - +          +- - - - - - - - - - + |
        |            |  | NVIDIA chip    |          | Ultrawide          | |
        |            |  | not used       |          | unplugged          | |
        |            |  +- - - - - - - - +          +- - - - - - - - - - + |
        |            +-----------------------------------------------------+
        v
+----------------+                               +--------------------+
| x11vnc         |  ---- over Tailscale ------>  | Mac Screen Sharing |
| :5900          |                               | connects           |
+----------------+                               +--------------------+
```

Xorg only uses the AMD chip, so the workaround never runs. The desktop starts, x11vnc starts, and the Mac connects:

```bash
open vnc://<server-tailscale-ipv4>:5900
```

---

## The fix: full NVIDIA driver, NVIDIA as the main GPU

```
 SOFTWARE              INSIDE THE LAPTOP
                     +-----------------------------------------------------+
+----------------+   |  +----------------+          +--------------------+ |
| Xorg (desktop) |----->| NVIDIA chip    |--------->| Ultrawide (HDMI)   | |
| running        |   |  | full driver:   |  direct  | desktop shown      | |
+----------------+   |  | display+compute|          +--------------------+ |
        |            |  +----------------+                                 |
        |            |          | copy for the laptop screen only          |
        |            |          v                                          |
        |            |  +----------------+          +--------------------+ |
        |            |  | AMD chip       |--------->| Laptop screen      | |
        |            |  +----------------+          | (panel broken)     | |
        |            |                              +--------------------+ |
        |            +-----------------------------------------------------+
        v
+----------------+                               +--------------------+
| x11vnc         |  ---- over Tailscale ------>  | Mac Screen Sharing |
| :5900          |                               | connects           |
+----------------+                               +--------------------+
```

The full driver has the display part, so NVIDIA draws the desktop and sends it straight to HDMI. The only copy left goes to the laptop screen, which is broken anyway. It's the same 595 series, so CUDA and Ollama keep working. The desktop uses about 200–300 MB of the GTX 1650's 4 GB.

### Steps

1. Install the full driver:
   ```bash
   sudo apt install nvidia-driver-595-server
   ```
2. Make NVIDIA the main GPU:
   ```bash
   sudo tee /etc/X11/xorg.conf.d/20-nvidia-primary.conf <<'EOF'
   Section "OutputClass"
       Identifier "nvidia-primary"
       MatchDriver "nvidia-drm"
       Driver "nvidia"
       Option "PrimaryGPU" "yes"
       ModulePath "/usr/lib/x86_64-linux-gnu/nvidia/xorg"
   EndSection
   EOF
   ```
3. Plug in the ultrawide and reboot:
   ```bash
   sudo reboot
   ```
   Until you reboot, `nvidia-smi` shows `Driver/library version mismatch` and the GPU can't be used for compute.

### Undo

If the screen stays black after the reboot, SSH in and run:

```bash
sudo rm /etc/X11/xorg.conf.d/20-nvidia-primary.conf && sudo reboot
```

---

## Recovering a frozen Xorg without a reboot

The frozen Xorg shows as `<defunct>` but keeps the display locked, so restarting GDM alone doesn't bring the desktop back. It runs as your user, so no sudo is needed to kill it:

```bash
ps -eo pid,ppid,stat,cmd | grep '[X]org'          # find the <defunct> Xorg and its parent (gdm-x-session)
kill -9 <xorg-pid> <gdm-x-session-pid>
```

GDM then logs in again automatically, and x11vnc starts with the new session. Check with:

```bash
systemctl --user is-active x11vnc
ss -lntp | grep 5900
```
