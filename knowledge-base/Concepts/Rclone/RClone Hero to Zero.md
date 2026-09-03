# RClone: Hero to Zero

`rclone` is a CLI tool that lets you **copy/sync files between local storage and cloud storage** (and between clouds) using a single interface. People use it because it’s scriptable, fast, resumable, and works well for large folder trees where GUIs fall over.

## Why people use rclone (real use cases)

- **Backups**: push a laptop/server/NAS folder to Google Drive, S3, Backblaze B2, etc.
- **Migrations**: move data from one cloud to another (e.g. Drive → S3).
- **Offsite archive**: keep an always-on box uploading in the background for days.
- **Automation**: cron jobs, CI tasks, and “set it and forget it” transfers.
- **Verification**: list and measure what’s in cloud paths (sizes, folder structure).

## Core concepts

- **Remote**: a named cloud config like `gdrive:` or `Gdrive:` (case-sensitive).
- **Paths**: transfers are `LOCAL_PATH` → `REMOTE:PATH`.
- **`copy` vs `sync`**:
  - `rclone copy`: additive; uploads missing files; **does not delete** destination files.
  - `rclone sync`: mirror; destination matches source; **can delete** destination files.
- **Quoting**: if local or remote paths contain spaces, quote the **entire** argument (`"<remote>:Folder With Spaces/"`).
- **Long-running jobs**: use `screen`/`tmux` so the transfer survives disconnects.

## Placeholders

- `<server_user>`, `<server_host>`: SSH target (Tailscale name or IP)
- `<mount_root>`: mount root (examples: `/media/<server_user>`, `/mnt`, `/srv`)
- `<source_folder>`: folder on the mounted disk to upload
- `<remote>`: rclone remote name (example: `Gdrive`)
- `<dest_folder>`: destination folder path in Drive
- `<session_name>`: `screen` session name (example: `rclone_upload`)

## Example: Google Drive upload hub (server + mounted disk)

This example is the “upload hub” pattern: an always-on Linux server with a disk attached uploads to Google Drive. You start the job in `screen` so you can close your laptop while it continues.

## Setup flow (minimal, reusable)

### 1) Laptop: confirm rclone remote exists

```bash
rclone config file
rclone listremotes
```

### 2) Server: copy your rclone config (avoid re-auth)

```bash
ssh <server_user>@<server_host> "mkdir -p ~/.config/rclone"
scp ~/.config/rclone/rclone.conf <server_user>@<server_host>:~/.config/rclone/rclone.conf
ssh <server_user>@<server_host> "rclone listremotes"
```

### 3) Server: locate mount + verify source path

```bash
lsblk -o NAME,SIZE,MOUNTPOINT,LABEL
df -h
ls "<mount_root>/<source_folder>/"
```

Detect leading/trailing spaces in folder names:

```bash
ls "<mount_root>/<source_folder>/" | cat -A
```

### 4) Server: confirm destination path in Drive

```bash
rclone lsd "<remote>:<dest_folder>/"
rclone size "<remote>:<dest_folder>/"
```

### 5) Server: run inside `screen` so it survives disconnects

```bash
sudo apt update && sudo apt install -y screen
screen -S <session_name>
```

Upload (additive, safe default):

```bash
rclone copy "<mount_root>/<source_folder>/" "<remote>:<dest_folder>/" -P --transfers 4
```

If you want to limit bandwidth (optional):

```bash
rclone copy "<mount_root>/<source_folder>/" "<remote>:<dest_folder>/" -P --transfers 4 --bwlimit 8M
```

Detach: `Ctrl+A` then `D`

Reattach later:

```bash
screen -r <session_name>
```

## Cheat sheet (commands)

### rclone essentials

```bash
rclone version
rclone config file
rclone listremotes
rclone config show
rclone lsd "<remote>:<dest_folder>/"
rclone size "<remote>:<dest_folder>/"
rclone copy "<src>/" "<remote>:<dest>/" -P --transfers 4
rclone copy "<src>/" "<remote>:<dest>/" --dry-run -P
```

### Common flags

```bash
-P                         # progress
--transfers 4              # parallel file uploads
--bwlimit 8M               # throttle bandwidth (omit for full speed)
--log-file rclone.log      # persistent logs
--log-level INFO           # DEBUG for deep troubleshooting
```

### Troubleshooting quick hits

```bash
rclone lsf "<remote>:<dest_folder>/"        # list files (flat)
rclone lsjson "<remote>:<dest_folder>/"     # inspect with JSON output
rclone about "<remote>:"                    # remote quota/usage (if supported)
```

### screen (unattended sessions)

```bash
screen -S <session_name>   # start
screen -ls                 # list
screen -r <session_name>   # reattach
```

### Path + mount sanity checks

```bash
lsblk -o NAME,SIZE,MOUNTPOINT,LABEL
df -h
ls "<mount_root>/<source_folder>/" | cat -A
```

