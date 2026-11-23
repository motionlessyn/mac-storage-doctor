#!/bin/bash
# mac-storage-doctor HIDDEN — 100% read-only. Finds the space that Finder,
# "About This Mac" and cache cleaners never show: swap, stale code-sign clones
# in /private/var/folders, app bundles hoarding old framework versions,
# silently downloaded AI models / VMs, updater leftovers, macOS update payloads.
# Also reconciles "disk used" against what is visible, so a big unexplained gap
# is surfaced instead of ignored. Deletes nothing.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"

line () { printf '%s\n' "--------------------------------------------------------------"; }
sz () { du -sh "$1" 2>/dev/null | awk '{print $1}'; }

echo "============== mac-storage-doctor hidden-space scan (read-only) =============="
echo

# --- 1. Triage: disk, RAM, swap, uptime -------------------------------------
echo "===== 1. Triage — why the Mac feels slow ====="
ram_b=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
free=$(free_kb)
echo "  Free on $(data_vol): $(human_kb "${free:-0}")"
echo "  RAM: $(human_b "$ram_b")"
swap_used=$(sysctl -n vm.swapusage 2>/dev/null | sed -n 's/.*used = \([0-9.]*\)M.*/\1/p')
[ -n "$swap_used" ] && echo "  Swap in use: ${swap_used}M (stored on disk in /System/Volumes/VM)"
boot=$(sysctl -n kern.boottime 2>/dev/null | sed -n 's/^{ sec = \([0-9]*\),.*/\1/p')
if [ -n "$boot" ]; then
  days=$(( ( $(date +%s) - boot ) / 86400 ))
  echo "  Last restart: $(date -r "$boot" '+%Y-%m-%d') ($days days ago)"
fi
# Verdicts
ram_gb=$(( ram_b / 1073741824 ))
free_gb=$(( ${free:-0} / 1048576 ))
target=20; [ "$ram_gb" -gt 8 ] && target=15
[ "$free_gb" -lt "$target" ] && echo "  ⚠ Under ${target} GB free: macOS cannot grow swap/caches; expect beachballs. Goal: ≥ ${target} GB."
swap_gb=$(awk -v s="${swap_used:-0}" 'BEGIN{printf "%d", s/1024}')
if [ "${swap_gb:-0}" -ge 4 ]; then
  echo "  ⚠ ${swap_gb} GB of swap on disk. A RESTART returns it immediately (often the single biggest, safest win)."
fi
[ "${days:-0}" -ge 14 ] && echo "  ⚠ No restart in ${days} days: swap and stale temp files keep piling up."
echo

# --- 2. Reconciliation: used vs visible ------------------------------------
echo "===== 2. Where is the space? (used vs visible) ====="
used_kb=$(df -k "$(data_vol)" 2>/dev/null | awk 'NR==2{print $3}')
echo "  Data volume used: $(human_kb "${used_kb:-0}")"
for p in /Applications "$HOME" /Library /private/var /opt /usr/local /Users/Shared; do
  [ -e "$p" ] && printf '    %-8s %s\n' "$(sz "$p")" "$p"
done
echo "  If /private/var is big, it is almost never logs — look at section 3."
echo "  (du counts APFS clones/hard links twice and skips unreadable dirs, so"
echo "   totals can exceed 'used'; use them to find WHERE, not exact sums.)"
echo

# --- 3. Per-user hidden folders in /private/var/folders --------------------
echo "===== 3. Hidden per-user folders (/private/var/folders) ====="
C=$(user_c_dir); X=$(user_x_dir); P=$(dirname "${C:-/nonexistent}")
if [ -d "$P" ]; then
  for d in "$P"/*; do [ -e "$d" ] && printf '    %-8s %s\n' "$(sz "$d")" "$d"; done
  echo "  Biggest entries in X/ (code-sign clones & scratch):"
  for d in "$X"/*; do [ -e "$d" ] && du -sh "$d" 2>/dev/null; done | sort -rh | head -8 | sed 's/^/    /'
  echo "  Biggest entries in C/ (per-user caches):"
  for d in "$C"/*; do [ -e "$d" ] && du -sh "$d" 2>/dev/null; done | sort -rh | head -6 | sed 's/^/    /'
fi
echo

# --- 4. Stale code-sign clones ----------------------------------------------
echo "===== 4. Stale code-sign clones (browsers copy their whole .app here) ====="
found=0
for d in "$X"/*.code_sign_clone; do
  [ -d "$d" ] || continue
  found=1
  id=$(basename "$d" .code_sign_clone)
  n=$(find "$d" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  state="app NOT running → all clones are stale (clean-hidden.sh can remove them)"
  app_running "$id" && state="app RUNNING → quit it first; one clone is in use"
  echo "  $id: $n clone(s), $(sz "$d") apparent — $state"
  find "$d" -mindepth 1 -maxdepth 1 -type d -exec stat -f '      %Sm  %N' -t '%Y-%m-%d %H:%M' {} \; 2>/dev/null | sort | tail -5
done
[ "$found" -eq 0 ] && echo "  (none)"
echo "  Note: clones share APFS blocks with the app, so real space < apparent."
echo "  The df delta after cleaning is the honest number."
echo

# --- 5. App bundles hoarding old framework versions ------------------------
echo "===== 5. Apps keeping old versions inside the bundle ====="
found=0
for v in /Applications/*.app/Contents/Frameworks/*.framework/Versions \
         "$HOME"/Applications/*.app/Contents/Frameworks/*.framework/Versions; do
  [ -d "$v" ] || continue
  cur=$(readlink "$v/Current" 2>/dev/null)
  n=0; kb=0
  for ver in "$v"/*; do
    b=$(basename "$ver")
    case "$b" in Current|A|"$cur") continue ;; esac
    [ -d "$ver" ] || continue
    n=$((n + 1)); kb=$((kb + $(size_kb "$ver")))
  done
  if [ "$n" -ge 1 ]; then
    found=1
    app=$(printf '%s' "$v" | sed 's:/Contents/.*::')
    echo "  $(basename "$app"): $n stale version(s), ~$(human_kb "$kb") (current: $cur)"
    echo "    Fix: quit the app, move it to the Trash, reinstall fresh. Do NOT delete"
    echo "    folders inside the bundle — it breaks the code signature."
  fi
done
[ "$found" -eq 0 ] && echo "  (none)"
echo "  Largest apps:"
du -sh /Applications/*.app "$HOME"/Applications/*.app 2>/dev/null | sort -rh | head -8 | sed 's/^/    /'
echo

# --- 6. AI models & VMs downloaded in the background -----------------------
echo "===== 6. AI models & virtual machines (often downloaded silently) ====="
for p in \
  "$HOME/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel" \
  "$HOME/Library/Application Support/Microsoft Edge/EdgeLLMOnDeviceModel" \
  "$HOME/Library/Application Support/Claude/vm_bundles" \
  "$HOME/.ollama/models" "$HOME/.lmstudio" "$HOME/.cache/lm-studio" \
  "$HOME/.cache/huggingface" "$HOME/.cache/torch" \
  "$HOME/Library/Containers/com.docker.docker" \
  "$HOME/Library/Containers/com.utmapp.UTM" "$HOME/Parallels" \
  "$HOME/Virtual Machines.localized" "$HOME/.orbstack"; do
  [ -e "$p" ] && printf '    %-8s %s\n' "$(sz "$p")" "$p"
done
[ -d "$HOME/.ollama/models/manifests" ] && find "$HOME/.ollama/models/manifests" -type f 2>/dev/null \
  | sed 's:.*/library/::; s:/:\::' | sed 's/^/      ollama model: /'
echo

# --- 7. Updater leftovers & duplicate CLI versions -------------------------
echo "===== 7. Updater leftovers & old CLI versions ====="
{
  for d in "$HOME"/Library/Caches/*.ShipIt "$HOME"/Library/Caches/*ShipIt* \
           "$HOME/Library/Application Support"/*Installer* \
           "$HOME/Library/Application Support/Google/GoogleUpdater"; do
    [ -e "$d" ] && du -sh "$d" 2>/dev/null
  done
} | sort -u | sort -rh | head -10 | sed 's/^/    /'
for vd in "$HOME/Library/Application Support/Claude/claude-code" \
          "$HOME/Library/Application Support/Claude/claude-code-vm" \
          "$HOME/.local/share/claude/versions"; do
  [ -d "$vd" ] || continue
  n=$(find "$vd" -mindepth 1 -maxdepth 1 ! -name '.*' | wc -l | tr -d ' ')
  if [ "$n" -gt 1 ]; then
    echo "    $n versions in $vd (newest is used; older ones are leftovers):"
    ls -1t "$vd" | tail -n +2 | while IFS= read -r o; do
      printf '      old: %-8s %s\n' "$(sz "$vd/$o")" "$vd/$o"
    done
  fi
done
echo

# --- 8. macOS-managed space -------------------------------------------------
echo "===== 8. macOS-managed space (report only) ====="
[ -d /Library/Updates ] && echo "    $(sz /Library/Updates)  /Library/Updates — downloaded macOS update; installing it frees this"
pend=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c 'com.apple.os.update')
[ "${pend:-0}" -gt 0 ] && echo "    $pend OS-update snapshot(s) — an update is staged; install it to release them"
tm=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c 'TimeMachine')
[ "${tm:-0}" -gt 0 ] && echo "    $tm Time Machine local snapshot(s) — purgeable, macOS thins them itself"
[ -f /private/var/vm/sleepimage ] && echo "    $(sz /private/var/vm/sleepimage)  sleepimage (= RAM size, normal, leave it)"
for p in "$HOME/Library/Application Support/MobileSync/Backup" \
         "$HOME/Library/Messages/Attachments" \
         "$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads" \
         "$HOME/Library/Mail"; do
  [ -e "$p" ] || continue
  s=$(sz "$p")
  [ -n "$s" ] && printf '    %-8s %s (user data — manage in the app, never rm)\n' "$s" "$p"
done
echo
line
echo "Next: present findings biggest-first, with the fix for each. Only the"
echo "code-sign clones have a scripted cleanup: bash $DIR/clean-hidden.sh"
