# tape-archive

Wraps ltfs so you can archive a directory to an LTO tape with one command,
interactively, from systemd, or from a pipeline.

## Image

Published to `ghcr.io/brianporeilly/tape-archive` by `.github/workflows/build.yml`:
`latest` tracks `main` (and is rebuilt weekly for Fedora base updates), and pushing a
`vX.Y.Z` git tag publishes `X.Y.Z` and `X.Y`.

```sh
sudo podman pull ghcr.io/brianporeilly/tape-archive:latest
```

To build locally instead (then set `TAPE_IMAGE=localhost/tape-archive:latest`):

```sh
sudo podman build -t localhost/tape-archive:latest .
```

The image is based on `fedora:44` and compiles the reference LTFS
(LinearTapeFileSystem/ltfs), so the binaries are `ltfs` and `mkltfs`
(not `altfs`). The LTFS release is pinned by `LTFS_REF` in the Containerfile; override it
with `--build-arg LTFS_REF=<tag|branch|commit>`.

## Install the host wrapper (Fedora CoreOS)

`/usr` is read-only; `/usr/local` is a symlink to `/var/usrlocal`.

```sh
sudo install -m 0755 tape-archive /var/usrlocal/bin/tape-archive
sudo tee /etc/tape-archive.env <<'EOF'
TAPE_IMAGE=ghcr.io/brianporeilly/tape-archive:latest
TAPE_DEVICE=/dev/sg1
TAPE_SOURCE=/var/mnt/data/to-archive
EOF
```

podman only pulls the image when it is missing; run `sudo podman pull "$TAPE_IMAGE"` to update.

## Use

```sh
tape-archive devices                           # list drives
tape-archive format --force --label ARC001     # DESTROYS tape contents
tape-archive archive --dry-run                 # preview
tape-archive archive --verify                  # copy, checksum-verify, unmount
tape-archive archive --dest 2026-photos --exclude '*.tmp'
tape-archive ls                                # read-only listing
tape-archive shell                             # mounted tape, interactive; clean unmount on exit
tape-archive raw                               # shell, no auto-mount (run ltfs yourself)

# one-off with a different source, without touching the env file:
TAPE_SOURCE=/var/mnt/other tape-archive archive
```

## NFS sources

Either mount NFS on the host and point `TAPE_SOURCE` at it:

```sh
sudo mount -t nfs -o ro nas:/export/data /var/mnt/nfs-source
```

or let podman manage it as a named volume (then `TAPE_SOURCE=nfs-source`):

```sh
sudo podman volume create --driver local \
  -o type=nfs -o o=addr=nas.example.lan,ro,nfsvers=4 -o device=:/export/data nfs-source
```

## Scheduling

```sh
sudo install -m 0644 tape-archive.service tape-archive.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now tape-archive.timer
journalctl -u tape-archive -f
```

For pipelines, call `tape-archive archive --verify` (non-zero exit on any failure, including
verification mismatches). Run `sudo systemctl start tape-archive.service` for an on-demand
run using the same config.

## Notes

- Unmounting is what writes the LTFS index. `tapectl` always unmounts on exit/SIGTERM and the
  wrapper sets a long `--stop-timeout`. Don't `kill -9` it mid-write.
- LTFS is append-only: deleting or overwriting files on tape does not free space. rsync is run
  with `--whole-file --no-inplace` and without perms/owners (LTFS doesn't store them).
- `/dev/sg1` can renumber across reboots; check with `tape-archive devices` or use a udev rule
  for a stable symlink and set `TAPE_DEVICE` to it.
- `--verify` reads the whole archive back from tape, which roughly doubles runtime.
