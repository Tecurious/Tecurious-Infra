# Rclone: Server “Upload Hub” to Google Drive (via Tailscale)

Use your Ubuntu server (reachable over Tailscale) as a long-running “upload hub” to push data from a locally-attached HDD/SSD to Google Drive using `rclone`, while your laptop can be shut down.

## Assumptions

- You can SSH into the server over Tailscale (example host: `saiserver`)
- Your external drive is mounted on the server (example path: `/media/vallaksa/LaCie/`)
- You already have an `rclone` Google Drive remote configured on your Mac (example remote name: `Gdrive:`)
- You want to upload a folder that contains subfolders like `Day 1`, `Day 2`, `Day 3`

## 1) Verify rclone config on your Mac

On **Mac**:

```bash
rclone config file
rclone listremotes
```

Confirm the remote name exactly (case-sensitive), e.g. `Gdrive:`.

## 2) Copy rclone config from Mac → Server

On **Server**:

```bash
mkdir -p ~/.config/rclone
```

On **Mac** (replace host if needed):

```bash
scp ~/.config/rclone/rclone.conf vallaksa@saiserver:~/.config/rclone/rclone.conf
```

On **Server**:

```bash
rclone listremotes
```

You should see the same remote name as on the Mac (e.g. `Gdrive:`).

## 3) Confirm source paths on the server (HDD/SSD)

On **Server**:

```bash
ls "/media/vallaksa/LaCie/"
ls "/media/vallaksa/LaCie/Rohit X Aparna/"
```

If any folder name contains spaces, always wrap the whole path in quotes.

### Detect “invisible” characters (leading/trailing spaces)

On **Server**:

```bash
ls "/media/vallaksa/LaCie/Rohit X Aparna/" | cat -A
```

Example output showing a leading space:

```text
Day 1$
Day 2$
 Day 3$
```

If you see a leading space (like ` Day 3`), rename it on disk before upload so Drive stays clean:

```bash
mv "/media/vallaksa/LaCie/Rohit X Aparna/ Day 3" "/media/vallaksa/LaCie/Rohit X Aparna/Day 3"
```

Re-check:

```bash
ls "/media/vallaksa/LaCie/Rohit X Aparna/" | cat -A
```

## 4) Confirm destination paths on Google Drive

On **Server** (remote + folder must be quoted as one argument):

```bash
rclone lsd "Gdrive:Rohit X Aparna/"
rclone size "Gdrive:Rohit X Aparna/"
```

## 5) Install and use `screen` for a long-running upload

If `screen` isn’t installed:

```bash
sudo apt update
sudo apt install -y screen
```

Start a named session:

```bash
screen -S wedding_upload
```

## 6) Run the upload

This copies from the server-mounted drive to Drive, **uploading only missing files** and **not deleting anything** on Drive.

Inside the `screen` session on **Server**:

```bash
rclone copy "/media/vallaksa/LaCie/Rohit X Aparna/" "Gdrive:Rohit X Aparna/" -P --transfers 4
```

Optional safety check before the real run:

```bash
rclone copy "/media/vallaksa/LaCie/Rohit X Aparna/" "Gdrive:Rohit X Aparna/" --dry-run -P
```

## 7) Detach, close laptop, reattach later

- Detach from `screen`: `Ctrl+A` then `D`
- You can close your laptop; the upload continues on the server

Later, SSH back into the server and reattach:

```bash
screen -r wedding_upload
```

List sessions:

```bash
screen -ls
```

## Notes

- Remote names are **case-sensitive** (`Gdrive:` is different from `gdrive:`).
- Quote the entire `remote:path` when the path contains spaces: `"Gdrive:Rohit X Aparna/"`.
- `rclone copy` is additive: it **does not delete** destination files. For mirroring (including deletions), use `rclone sync` only when you’re sure.

