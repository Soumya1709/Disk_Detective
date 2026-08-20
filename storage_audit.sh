#!/bin/bash
#
# storage_audit.sh
# DiskDetective - automated storage audit: finds disk hogs, stale files,
# demonstrates hard vs symbolic links, and cold-archives old data to a
# loopback-mounted virtual disk.
#
# Run as root: sudo ./storage_audit.sh
#
# NOTE ON set -e: pipelines using `sort`/`head` can trigger SIGPIPE on the
# upstream command when the reader exits early, which is harmless here but
# would abort the script under strict -e. We deliberately do NOT use
# `set -e` for that reason and instead check exit codes where it matters.
set -uo pipefail

DATA_DIR="/data"
REPORT="storage_audit.txt"
ARCHIVE_IMG="/home/$(logname)/coldarchive.img"
ARCHIVE_MOUNT="/mnt/coldarchive"
STALE_DAYS=180

echo "=== Phase 0: Test data setup (idempotent) ==="
mkdir -p "$DATA_DIR/renders" "$DATA_DIR/footage"

if [ ! -f "$DATA_DIR/renders/final_cut_v3.mp4" ]; then
    dd if=/dev/zero of="$DATA_DIR/renders/final_cut_v3.mp4" bs=1M count=150 status=none
    dd if=/dev/zero of="$DATA_DIR/footage/raw_footage_2024.mov" bs=1M count=200 status=none
    dd if=/dev/zero of="$DATA_DIR/renders/small_clip.mp4" bs=1M count=20 status=none
    touch -d "300 days ago" "$DATA_DIR/footage/old_project_backup.mov"
    touch -d "250 days ago" "$DATA_DIR/renders/abandoned_edit.mp4"
    touch -d "10 days ago" "$DATA_DIR/renders/recent_work.mp4"
    touch "$DATA_DIR/footage/trainee1_project.mov"
    chown trainee1 "$DATA_DIR/footage/trainee1_project.mov" 2>/dev/null || true
    echo "Test dataset created under $DATA_DIR"
else
    echo "Test dataset already present, skipping creation"
fi

echo
echo "=== Phase 1: Filesystem survey ==="
lsblk
df -h
echo "--- Top-level directory sizes under $DATA_DIR ---"
du -sh "$DATA_DIR"/* 2>/dev/null | sort -rh

echo
echo "=== Phase 2: The hunt ==="
echo "--- Files over 100MB ---"
find "$DATA_DIR" -type f -size +100M 2>/dev/null
echo "--- Files not modified in ${STALE_DAYS}+ days ---"
find "$DATA_DIR" -type f -mtime +${STALE_DAYS} 2>/dev/null
echo "--- Files owned by trainee1 ---"
find "$DATA_DIR" -type f -user trainee1 2>/dev/null

echo
echo "=== Phase 3: Links investigation ==="
echo "original content" | tee "$DATA_DIR/testfile.txt" > /dev/null
ln -f "$DATA_DIR/testfile.txt" "$DATA_DIR/hardlink.txt"
ln -sf "$DATA_DIR/testfile.txt" "$DATA_DIR/symlink.txt"
echo "--- Inode comparison (hardlink shares inode, symlink does not) ---"
ls -li "$DATA_DIR/testfile.txt" "$DATA_DIR/hardlink.txt" "$DATA_DIR/symlink.txt"
rm -f "$DATA_DIR/testfile.txt"
echo "--- After deleting original: hardlink still readable ---"
cat "$DATA_DIR/hardlink.txt" 2>&1
echo "--- After deleting original: symlink is now broken ---"
cat "$DATA_DIR/symlink.txt" 2>&1 || echo "(confirmed broken, as expected)"

echo
echo "=== Phase 4: Report building -> $REPORT ==="
{
  echo "===== STORAGE AUDIT REPORT - $(date) ====="
  echo
  echo "--- Filesystem Overview ---"
  df -h
  echo
  echo "--- Top 10 Largest Directories ---"
  du -sh "$DATA_DIR"/* 2>/dev/null | sort -rh | head -10
  echo
  echo "--- Files Over 100MB ---"
  find "$DATA_DIR" -type f -size +100M 2>/dev/null
  echo
  echo "--- Stale Files (not modified in ${STALE_DAYS}+ days) ---"
  find "$DATA_DIR" -type f -mtime +${STALE_DAYS} 2>/dev/null
  echo
  echo "--- Total File Count ---"
  find "$DATA_DIR" -type f 2>/dev/null | wc -l
  echo
  echo "--- Reclaimable Space (stale files only) ---"
  find "$DATA_DIR" -type f -mtime +${STALE_DAYS} -exec du -ch {} + 2>/dev/null | tail -1
} | tee "$REPORT"

echo
echo "=== Phase 5: Cold archive via loopback virtual disk ==="
if losetup -a | grep -q "$ARCHIVE_IMG"; then
    echo "Archive image already attached, skipping loop setup"
    LOOP_DEV=$(losetup -a | grep "$ARCHIVE_IMG" | cut -d: -f1)
else
    if [ ! -f "$ARCHIVE_IMG" ]; then
        dd if=/dev/zero of="$ARCHIVE_IMG" bs=1M count=300 status=none
    fi
    LOOP_DEV=$(losetup -f)
    losetup -fP "$ARCHIVE_IMG"
    mkfs.ext4 -F "$LOOP_DEV" > /dev/null
fi
echo "Using loop device: $LOOP_DEV"

mkdir -p "$ARCHIVE_MOUNT"
if ! mount | grep -q "$ARCHIVE_MOUNT"; then
    mount "$LOOP_DEV" "$ARCHIVE_MOUNT"
fi

echo "--- Copying stale files to cold archive ---"
find "$DATA_DIR" -type f -mtime +${STALE_DAYS} -exec cp -n {} "$ARCHIVE_MOUNT"/ \; 2>/dev/null
ls -la "$ARCHIVE_MOUNT"

echo
echo "=== Phase 6: Archive evidence appended to $REPORT ==="
{
  echo
  echo "===== ARCHIVE STEP EVIDENCE - $(date) ====="
  echo "--- losetup -a ---"; losetup -a
  echo "--- mount | grep coldarchive ---"; mount | grep coldarchive
  echo "--- df -h (archive mount) ---"; df -h | grep coldarchive
  echo "--- Archived files ---"; ls -la "$ARCHIVE_MOUNT"
} >> "$REPORT"

echo
echo "=== Storage audit complete. Report saved to $REPORT ==="
