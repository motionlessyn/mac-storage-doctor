---
name: mac-storage-doctor
description: Audit and safely reclaim disk space on a Mac, including the hidden space Finder, "About This Mac" and cache cleaners never show (swap, stale browser code-sign clones in /private/var/folders, apps hoarding old versions inside their bundle, silently downloaded AI models and VMs, staged macOS updates). Use whenever the user says their Mac is full, slow, out of space, gets a "startup disk almost full" warning, asks what is eating their storage, wants to free space, clear caches or remove junk — in any language (e.g. "my mac is out of space", "free up disk", "what's taking up my storage", French "libère de l'espace", "mon ordi rame", "stockage plein", "fais un audit de mon disque", Spanish "mi mac no tiene espacio"). Measures first, explains in plain words, auto-clears only pure caches, makes everything else reversible or asks, logs every deletion and reports the real before/after. Do NOT use for cloud storage or a single app's own in-app cache button.
---

# Mac Storage Doctor

Find **where the space really went**, then free it the way a careful engineer
would: measure first, delete only what provably regenerates, make anything
riskier reversible, ask before anything expensive, log every action, report
honestly.

Built on [mac-storage-cleaner](https://github.com/davila7/claude-code-templates)
(MIT). The cache tiers and scripts come from there; this skill adds a
**hidden-space scan** for the gigabytes that cleaners skip. On real Macs these
are often bigger than every cache combined:

| Hidden hog | Typical size | Why nobody sees it |
|---|---|---|
| Swap files after weeks without a restart | 5–20 GB | lives in `/System/Volumes/VM` |
| Browser **code-sign clones** left by crashes/force-quits | 1–90+ GB | `/private/var/folders/…/X/`, never shown in Finder |
| App bundle keeping **old framework versions** (Chrome: one per update) | 5–12 GB | inside the `.app`, Finder shows one icon |
| On-device AI models (Chrome Gemini Nano, Ollama, LM Studio) and VMs | 4–20 GB | auto-downloaded in app support folders |
| Staged macOS update + its snapshots | 2–10 GB | `/Library/Updates`, APFS snapshots |

Scripts live in `scripts/`. Tiers, exact commands and gotchas live in
`references/cache-catalog.md`. Read the catalog whenever something is not
classified by a script.

## Core principles

- **Explain in the user's language, plainly.** Many users are not technical:
  say "copies of Chrome left behind" rather than "code_sign_clone dirs".
- **Safe tier → delete outright.** Pure caches; the only cost is a slower next run.
- **Everything else → Trash or ask.** Use `trash-items.sh` (reversible). Never
  hard-delete user data.
- **When unsure, demote a tier.**
- **Never touch the agent's own app data** (the Claude/Cursor/VS Code app you are
  running inside: its VM bundles, caches, databases) unless the user names it.
  Point to the app's own settings instead.
- **Never `sudo`.** Never delete inside a signed `.app` bundle (breaks its signature):
  reinstall the app instead.
- **Every destructive run is logged** to `~/Library/Logs/mac-storage-doctor/operations.log`.

## Workflow

**Locating the scripts.** Each block re-resolves `$D` (shell state does not persist):

```bash
D="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/mac-storage-doctor}"; D="${D:-$HOME/.claude/skills/mac-storage-doctor}"
```

### 1. Hidden-space scan + triage (always first, read-only, ~1 min)

```bash
D="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/mac-storage-doctor}"; D="${D:-$HOME/.claude/skills/mac-storage-doctor}"
bash "$D/scripts/find-hidden.sh"
```

Reports free space, RAM, swap on disk and days since the last restart, then
reconciles **disk used vs. visible folders** and drills into whatever is
unexplained (usually `/private/var`). Read the verdict lines (⚠):

- **Low RAM (≤ 8 GB) + low free space** is why the Mac is slow: macOS has no room
  to swap. Target ≥ 20 GB free on 8 GB machines, ≥ 15 GB otherwise.
- **Swap ≥ 4 GB or no restart in 14+ days** → the first recommendation is
  *restart the Mac*. It is free, instant and safe.
- **Code-sign clones** → step 4.
- **App with stale versions** → tell the user to quit the app, Trash it and
  reinstall (settings and profile live outside the bundle and are kept).
- **AI models** → explain what each is and how to disable it at the source
  (see catalog). Otherwise it downloads again.
- **Staged macOS update** → installing it frees the payload and its snapshots.

### 2. Cache survey (read-only)

```bash
D="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/mac-storage-doctor}"; D="${D:-$HOME/.claude/skills/mac-storage-doctor}"
bash "$D/scripts/survey.sh"
```

Sizes every cache that exists on this Mac, grouped **safe / ask / never / app data**.

### 3. Present the audit, then act

Give one table, **biggest first**, with three groups:
1. *Safe, I can do it now* (safe-tier caches, stale installers already installed as apps).
2. *You need to do it* (restart, reinstall an app, disable an AI model, install a macOS update).
3. *Your call* (ask tier: models, VMs, big apps you may not use, old Downloads).

Get a yes before deleting anything. The user's yes to "do the safe group" covers
exactly that group. Then:

```bash
D="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/mac-storage-doctor}"; D="${D:-$HOME/.claude/skills/mac-storage-doctor}"
bash "$D/scripts/clean-safe.sh"
```

For browser/Electron caches, ask the user to quit the app first. Delete only the
`Cache`/`Code Cache`/`GPUCache` subfolders and **never** the whole app folder.

### 4. Stale code-sign clones (needs the app quit)

Ask the user to quit the app with Cmd+Q, then preview the removal and run it:

```bash
D="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/mac-storage-doctor}"; D="${D:-$HOME/.claude/skills/mac-storage-doctor}"
bash "$D/scripts/clean-hidden.sh" --dry-run && bash "$D/scripts/clean-hidden.sh"
```

The script skips any app that is still running and reports the **real** df
delta. Clones share APFS blocks with the app, so the size `du` shows is larger
than what you actually get back. If the app's bundle also holds stale versions,
reinstall it afterwards, or each future clone will be huge again.

### 5. Beyond caches (read-only)

```bash
D="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/mac-storage-doctor}"; D="${D:-$HOME/.claude/skills/mac-storage-doctor}"
bash "$D/scripts/find-extras.sh"
```

Lists leftovers of uninstalled apps, files over 500 MB, stale installers and old
Downloads. All of these are ask tier, so remove them reversibly:
`bash "$D/scripts/trash-items.sh" "/path/one" "/path/two"`.
Confirm that an app is really uninstalled before you remove its leftovers.

### 6. Report

In the user's language, give:
- free space before → after, measured with `df -h /System/Volumes/Data`;
- what was removed and how big it was;
- what is left for the user to do, with the expected gain for each;
- the path of the log.

If df moved less than expected, explain APFS purgeable space and snapshots.
Do not chase that space with `sudo`.

## Safety rules

- **Never delete** iOS backups, the Photos library, Mail or Messages data, whole
  app-support folders, `~/.ssh`, `~/.aws`, keychains or Time Machine snapshots.
  Report their size only.
- **Messaging apps' media is user data.** Send the user to the app's own "Clear
  cache" setting instead.
- **Never `sudo`** into `/System`, `/Library/Caches` or SIP-protected areas. In
  `/private/var/folders`, the only thing this skill removes is stale
  `*.code_sign_clone` folders in the user's own `X/` dir, via `clean-hidden.sh`.
- **Never edit inside a `.app` bundle**, even to delete old versions: reinstall the app.
- **`rm -rf a b c` keeps going after an error.** Check each path afterwards with `du`.
- Some safety layers block `rm -rf` with globs or relative paths. Use the
  scripts, or absolute paths listed one by one.
