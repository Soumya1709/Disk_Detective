# DiskDetective — Storage Audit

## Problem Statement
A shared RHEL file server has hit 96% disk usage. Editors can't save new
renders, and nobody knows what's consuming the space — the suspicion is years
of abandoned project files and duplicate footage.

This project produces an automated storage audit that locates disk hogs,
identifies stale files, and generates a clean, readable cleanup report —
without anyone having to manually eyeball the filesystem.

## Approach
- **Filesystem survey**: `lsblk`, `df -h`, and `du -sh | sort -rh` establish
  which mount point is under pressure and which top-level directories are the
  biggest contributors, before drilling into individual files.
- **The hunt**: `find` locates three categories independently — large files
  (`-size +100M`), stale files (`-mtime +180`), and files owned by a specific
  user (`-user`) — each piped through `2>/dev/null` so permission-denied
  noise from inaccessible directories doesn't pollute the report.
- **Links investigation**: creates a hard link and a symbolic link to the
  same file, then deletes the original to demonstrate the core Linux
  filesystem concept directly — a hard link *is* another name for the same
  inode (data survives), while a symlink is a path reference (breaks when
  the target disappears). `ls -li` proves this by showing matching vs
  differing inode numbers.
- **Report building**: all findings are combined into one report using
  redirection and pipes (`>`, `>>`, `|`, `tee`, `sort`, `head`, `wc -l`), with
  stderr discarded throughout so the report stays clean.
- **Archive**: rather than requiring a physical/VMware second disk, this
  build uses a loopback-mounted disk image (`dd` + `losetup` + `mkfs.ext4`) —
  it behaves identically to a real block device (partition, format, mount)
  without any VMware hardware configuration, and is fully reproducible on any
  machine running the script.

## Test Data Note
Since this is a lab VM rather than a genuinely aged production server, the
script seeds realistic test data first (`/data/renders`, `/data/footage`)
using `dd` for large files and `touch -d` to backdate modification times, so
the "180+ day stale file" and "100MB+ large file" logic has real matches to
find. This mirrors the business case's conditions without requiring months of
real usage.

## Repository Structure
```
.
├── README.md
├── storage_audit.sh          # builds the test data, runs the full audit, archives stale files
├── commands.txt               # full command log, including failed attempts
├── storage_audit.txt         # generated report (top 10 largest, stale files, reclaimable space)
└── screenshots/
    ├── links-inode-comparison.png
    ├── hardlink-survives-deletion.png
    └── loopback-archive-mounted.png
```

## How to Run
```bash
sudo ./storage_audit.sh
cat storage_audit.txt
```

## Demo Video
[link to be added — walkthrough of the filesystem survey, the find commands,
the hard link vs symlink deletion demo, and the loopback archive mount]
