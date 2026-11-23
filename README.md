# Mac Storage Doctor 🩺

A Claude Code skill that **audits your Mac's disk and safely frees space**,
including the hidden gigabytes that Finder, "About This Mac" and every cache
cleaner skip.

> 🇫🇷 Un skill Claude Code qui fait l'audit du stockage de ton Mac et libère de
> l'espace sans risque, y compris les Go cachés que le Finder et les nettoyeurs
> ne montrent jamais. Dis simplement « mon ordi rame, libère de l'espace ».

## Why another cleaner?

Cache cleaners look in `~/Library/Caches`. On a real 8 GB MacBook, the space had
gone somewhere else:

| Found | Size | Seen by cache cleaners? |
|---|---|---|
| 8 leftover copies of Chrome in `/private/var/folders/…/X/` (left by crashes) | **92 GB** apparent | ❌ (they're told to never look there) |
| Chrome.app holding **19 old versions** of itself | 11 GB (should be 0.7 GB) | ❌ |
| Swap files after 27 days without a restart | 18 GB | ❌ |
| Chrome's on-device AI model (Gemini Nano) | 4 GB | ❌ |
| Staged macOS update + snapshots | 2 GB+ | ❌ |
| Regular caches (Codex, browsers, Homebrew…) | 8 GB | ✅ |

The disk was 99% full (2.8 GB free) and the Mac was crawling. Cleaning the caches
alone freed 8 GB. What was hidden was several times bigger.

## What it does

1. **Triage.** Checks free space, RAM, swap and days since the last restart, and
   explains in plain words why the Mac is slow.
2. **Reconciliation.** Compares disk used with visible folders, then drills into
   whatever doesn't add up.
3. **Hidden-space scan.** Covers code-sign clones, apps hoarding old versions,
   AI models and VMs, updater leftovers and staged macOS updates.
4. **Cache survey.** Sorts caches into tiers: safe, ask, never.
5. **Audit table.** Shows the findings biggest-first, split into *I can do it*,
   *you need to do it* and *your call*.
6. **Cleanup.** Deletes only what you approve. Pure caches are removed, anything
   else goes to the Trash (reversible). Every action is logged.
7. **Report.** Gives the real before/after free space, measured with `df` rather
   than guessed.

## Safety

- Read-only until you say yes.
- Never `sudo`. Never edits inside a signed `.app` bundle: it tells you to
  reinstall the app instead.
- Never touches iOS backups, Photos, Mail, Messages, keychains or Time Machine,
  nor the app data of the AI agent it runs in.
- Removes code-sign clones only when their app is **not running**.
- Log: `~/Library/Logs/mac-storage-doctor/operations.log`.
- Plain bash 3.2 (the version macOS ships) with no dependencies.

## Install

**As a plugin (Claude Code):**

```
/plugin marketplace add motionlessyn/mac-storage-doctor
/plugin install mac-storage-doctor@mac-storage-doctor
```

**As a standalone skill:**

```bash
git clone https://github.com/motionlessyn/mac-storage-doctor /tmp/msd && \
  cp -R /tmp/msd/skills/mac-storage-doctor ~/.claude/skills/
```

Then ask Claude: *"my Mac is out of space, audit it"*, or
*« libère de l'espace sur mon ordi »*.

**Just the scan, no Claude:**

```bash
bash ~/.claude/skills/mac-storage-doctor/scripts/find-hidden.sh
```

## Files

```
skills/mac-storage-doctor/
├── SKILL.md                  workflow for Claude
├── references/cache-catalog.md   tiers, exact commands, gotchas, hidden-space table
└── scripts/
    ├── find-hidden.sh        NEW: triage + hidden space (read-only)
    ├── clean-hidden.sh       NEW: removes stale code-sign clones (app must be quit)
    ├── survey.sh             cache survey (read-only)
    ├── clean-safe.sh         clears the safe cache tier
    ├── find-extras.sh        app leftovers, big files, old downloads (read-only)
    ├── trash-items.sh        reversible delete via Finder
    └── lib.sh                shared tiers & helpers
```

## Credits

Built on [mac-storage-cleaner](https://github.com/davila7/claude-code-templates/tree/main/cli-tool/components/skills/productivity/mac-storage-cleaner)
by Daniel (San) Ávila (MIT): the cache tiers, the survey, the safe cleanup and
the Trash/log design come from that project. Ideas also come from
[free-disk-space](https://github.com/OutThisLife/brooklyn-skills) (never touch
the agent's own data). MIT licensed.
