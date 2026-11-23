#!/bin/bash
# mac-storage-doctor CLEAN-HIDDEN — removes stale code-sign clones only.
# Chromium browsers (Chrome, Edge, Brave…) copy their entire .app into
# /private/var/folders/<hash>/X/<bundle-id>.code_sign_clone on launch/update and
# are meant to delete it on quit. Crashes and force-quits leave them behind,
# sometimes 10+ GB each. A clone is stale once its app is NOT running.
#
# Safety: per-user dir only (resolved with getconf, never hard-coded), never
# sudo, skips any app that is running, logs every removal, reports the real df
# delta (clones share APFS blocks, so du overstates the gain).
# Usage: clean-hidden.sh            remove clones of every app that is not running
#        clean-hidden.sh --dry-run  show what would be removed
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"

dry=0; [ "${1:-}" = "--dry-run" ] && dry=1
X=$(user_x_dir)
case "$X" in /var/folders/*/X|/private/var/folders/*/X) ;; *) echo "Unexpected per-user dir: '$X' — aborting."; exit 1 ;; esac
[ -d "$X" ] || { echo "No per-user X dir; nothing to do."; exit 0; }

log_writable || echo "⚠ Cannot write the audit log — this run will NOT be recorded."
before=$(free_kb)
did=0
for d in "$X"/*.code_sign_clone; do
  [ -d "$d" ] || continue
  id=$(basename "$d" .code_sign_clone)
  case "$id" in *[!A-Za-z0-9.-]*|"") echo "  skip (odd name): $d"; continue ;; esac
  if app_running "$id"; then
    echo "  skip: $id is running — quit it (Cmd+Q) and re-run"
    log_op skipped "running" "$d"
    continue
  fi
  apparent=$(du -sh "$d" 2>/dev/null | awk '{print $1}')
  if [ "$dry" -eq 1 ]; then
    echo "  would remove: $d ($apparent apparent)"
    continue
  fi
  rm -rf "$d" 2>/dev/null
  if [ -e "$d" ]; then
    echo "  could not fully remove (in use or protected): $d"
    log_op skipped "$apparent" "$d"
  else
    echo "  removed: $d ($apparent apparent)"
    log_op removed "$apparent" "$d"
    did=1
  fi
done
[ "$dry" -eq 1 ] && exit 0
after=$(free_kb)
if [ "$did" -eq 1 ]; then
  echo
  echo "Real space recovered (df delta): $(human_kb $(( ${after:-0} - ${before:-0} )))"
  echo "Free now: $(human_kb "${after:-0}")"
else
  echo "Nothing removed."
fi
echo "Log: $LOG_DIR/operations.log"
