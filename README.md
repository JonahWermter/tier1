[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Windows](https://img.shields.io/badge/Windows-10%2F11-0078D4?logo=windows)](https://www.microsoft.com/windows)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-required-blueviolet)](https://claude.ai/code)

# Tier1

AI-guided Windows troubleshooting — the helpdesk methodology that belongs on your machine, not in a ticket queue.

---

## What it does

You describe the problem. Tier1 investigates — silently collecting system data, reading event logs, checking services, and pattern-matching against known Windows failure modes. It proposes a fix, shows you exactly what will change and how to undo it, and waits for your go-ahead before touching anything.

After the fix, Tier1 explains what was actually wrong, why it happened, and what the change did. You walk away understanding your machine better than before.

The core loop:

1. **Research first.** Collection runs silently before any diagnosis. You see what was gathered and why.
2. **Approval gate.** Nothing changes without your explicit approval. The rollback plan is shown before the change diff — before you decide.
3. **Rollback required.** Every fix that modifies the system needs a verified undo path. No restore point, no fix.
4. **Plain-English explanation.** What was wrong, why, what changed, and where the rollback artifacts are.

---

## How a session looks

A realistic walkthrough of a Windows Update failure — the actual session shape from problem intake through post-fix explanation.

```
You: Windows Update keeps failing at 47% with error code 0x80070003.
     It's happened three times since yesterday.

Tier1: > Collecting system data...

       I collected the following to diagnose your issue:
       - OS version: to check that proposed fixes are compatible with your Windows edition
       - Last 50 System and Application event log entries: to find error patterns pointing
         to the root cause
       - Stopped services: to identify services that stopped unexpectedly
       - C: drive free space: to rule out disk pressure as a contributing factor

       Findings: The System event log shows repeated failures in the Windows Update service
       (wuauserv) with "Access is denied" errors on files in C:\Windows\SoftwareDistribution\
       Download. The SoftwareDistribution folder is the staging area for update packages —
       when it becomes corrupted or locked, updates fail consistently at the same percentage.
       The error pattern here matches a stale download cache, not a permissions or network
       problem.

       ---
       **Rollback plan:**
       If something goes wrong after this fix, here's how to undo it:
       - System Restore point from 2026-05-18 (3 days ago). To use: Settings > Update &
         Security > Recovery > Open System Restore > choose this point.
       - No files are deleted permanently — the SoftwareDistribution folder is renamed, not
         removed. To manually reverse: rename C:\Windows\SoftwareDistribution.bak back to
         C:\Windows\SoftwareDistribution, then restart the wuauserv service.

       **What changes:**
       - Windows Update service (wuauserv) and its dependencies are stopped
       - C:\Windows\SoftwareDistribution\Download is renamed to Download.bak
         (preserving the original, not deleting it)
       - Services are restarted
       - Windows Update will re-download current update packages on next run
       - Time estimate: 2-3 minutes. Restart required: No.

       **Confidence: HIGH** | Error pattern matches SoftwareDistribution cache corruption.
       Windows 11 Pro — compatible. Restore point verified 3 days ago.

       How would you like to proceed?
       - **Approve** — I'll run the fix now
       - **Skip this fix** — Move on without making this change
       - **I'll do this myself** — Show me the commands to run manually
       ---

[You select: Approve]

Tier1: Fix complete. Windows Update re-ran successfully.

       **What was wrong:** The Windows Update download cache (SoftwareDistribution\Download)
       contained a corrupted or partially-written package file that the update service kept
       trying — and failing — to process.

       **Why it happened:** Update downloads can be interrupted by a power event, a sudden
       service stop, or a brief disk error. When the incomplete file is left in place, the
       update service re-attempts from the cached (broken) state on every retry instead of
       starting fresh.

       **What changed:** The Download subfolder was renamed to Download.bak, which forced
       Windows Update to treat the staging area as empty and download a clean copy of the
       pending update.

       **Why the fix worked:** Renaming rather than deleting preserves the original files
       in case inspection is needed, while removing the lock the update service held on
       the corrupted content.

       **If something seems off later:** The original cache is at
       C:\Windows\SoftwareDistribution\Download.bak. To restore it: stop wuauserv, rename
       Download.bak back to Download, restart wuauserv.
```

The key thing here: you see the rollback path before the change diff, and you see both before you're asked to approve.

---

## Domains covered

Tier1 covers five Windows problem areas. Break-fix is fully built out; guided implementation ("help me do this") is actively expanding.

| Domain | Break-fix | Guided Implementation |
|---|---|---|
| **General Windows** | Service failures, Windows Update errors, SFC/DISM, DLL/runtime errors | Coming soon |
| **Gaming Mods** | Mod manager crashes, mod conflicts, load order, script extender failures | Coming soon |
| **Outlook / M365** | Profile corruption, add-in failures, send/receive errors, OST/PST problems | Coming soon |
| **Network / Connectivity** | No internet, Wi-Fi failures, DNS, adapter errors, IP conflicts | Up next |
| **BSOD Analysis** | Minidump analysis, driver fault identification, stop code interpretation | Coming soon |

---

## Why it's safe

Tier1 classifies every proposed fix into one of three risk tiers before showing it to you.

**Tier 1** (read-only diagnostics, event log queries) — runs without a gate.
**Tier 2** (service restarts, targeted registry writes, file renames) — requires your approval, rollback plan shown first.
**Tier 3** — refused outright. No approval gate, no workaround, no amount of asking will change that.

Hard-refused operations:

- **BCD / boot configuration edits** — boot config errors can leave Windows unbootable with no in-session recovery path.
- **diskpart on existing volumes** — format, delete partition, clean — permanent data loss that System Restore can't reverse.
- **Disabling Windows Defender** — Tier1 will not weaken system security posture regardless of the stated justification.
- **HKLM\SYSTEM\CurrentControlSet writes** — driver/hardware layer changes with reboot-persistent effects beyond safe rollback.

The full tier taxonomy, hard limits list, confidence criteria, and rollback patterns are in [`references/safety-protocols.md`](references/safety-protocols.md).

---

## Under the hood

Tier1 is a set of [Claude Code](https://claude.ai/code) skills and agents. There's no application code, no runtime, no dependencies beyond PowerShell 5.1 (which is already on every Windows 10/11 machine). The whole system is structured Markdown that Claude Code interprets at session time.

### Orchestration

| File | Role |
|---|---|
| [`.claude/skills/tier1/SKILL.md`](.claude/skills/tier1/SKILL.md) | Main skill — problem intake, silent collection, intent classification, domain routing, approval gates, execution, post-fix explanation |
| [`.claude/skills/tier1-safety/SKILL.md`](.claude/skills/tier1-safety/SKILL.md) | Shared safety protocols injected into every domain agent — tier taxonomy, hard limits, confidence criteria, rollback patterns |

### Domain agents

These skip the routing step and go straight to a specific domain. All share the same safety protocols.

| Agent | Domains | File |
|---|---|---|
| `tier1-system` | General Windows + BSOD | [`.claude/agents/tier1-system.md`](.claude/agents/tier1-system.md) |
| `tier1-apps` | Gaming Mods + Outlook/M365 | [`.claude/agents/tier1-apps.md`](.claude/agents/tier1-apps.md) |
| `tier1-network` | Network / Connectivity | [`.claude/agents/tier1-network.md`](.claude/agents/tier1-network.md) |

### Domain knowledge base

Each reference file is a complete diagnostic methodology — not a list of canned answers, but a reasoning framework with diagnosis logic, confidence criteria, fix tiers, rollback strategies, and post-fix explanations.

| Reference | Lines | Covers |
|---|---|---|
| [`references/windows-general.md`](references/windows-general.md) | 458 | DLL/runtime failures, Windows Update, SFC/DISM/chkdsk, service failures |
| [`references/bsod.md`](references/bsod.md) | 424 | Stop code table (~20 codes), minidump pattern detection, driver fault correlation |
| [`references/gaming-mods.md`](references/gaming-mods.md) | 485 | Vortex/MO2/NMM, load order conflicts, mod safety checks (signature verification) |
| [`references/outlook-m365.md`](references/outlook-m365.md) | 523 | Profile corruption, add-in failures, OST rebuild, M365 auth |
| [`references/network.md`](references/network.md) | 496 | IP config, DNS, adapter reset, Wi-Fi, graduated cascade with per-step approval |
| [`references/safety-protocols.md`](references/safety-protocols.md) | 239 | Tier taxonomy, hard limits, confidence criteria, rollback artifact patterns |
| [`references/gi-template.md`](references/gi-template.md) | 169 | Template spec for guided implementation sections |

### Safety scripts

Two PowerShell 5.1 scripts that run before any fix is proposed. No external modules required.

| Script | Purpose |
|---|---|
| [`scripts/safety/detect-version.ps1`](scripts/safety/detect-version.ps1) | Detects Windows edition, architecture, S Mode, LTSC, execution policy |
| [`scripts/safety/check-rollback.ps1`](scripts/safety/check-rollback.ps1) | Validates System Restore / VSS state — hard stop if rollback infrastructure is missing |

---

## Getting started

See [INSTALL.md](INSTALL.md) for detailed setup, including global install for power users.

You need Windows 10 or 11 and [Claude Code](https://claude.ai/code).

```powershell
git clone https://github.com/JonahWermter/tier1.git
cd tier1
claude
```

Then:

```
/tier1 'Windows Update stuck at 0% for two hours'
```

---

## Status

**v1.0** — break-fix across all 5 domains is complete and functional.

**v1.1** — in active development. Expanding into guided implementation ("help me set up a VPN", "walk me through enabling BitLocker"). The intent routing infrastructure is built; network domain is the proving ground before rolling it out to the rest.

---

## Privacy

Tier1 runs locally. No telemetry, no third-party services, no additional data collection beyond what Claude Code itself uses. Nothing is stored between sessions.

---

## Disclaimer

Tier1 runs PowerShell commands on your system as directed by an AI model. It includes safety tiers, confirmation gates, and rollback verification, but **you are responsible for reviewing every proposed action before approving it.** This is a work in progress under active development — provided "as is" with no warranty of any kind. See [LICENSE](LICENSE) for full terms. Use at your own risk.

---

## License

Apache 2.0. See [LICENSE](LICENSE).

---

<sub>Built with [Claude Code](https://claude.ai/code). Project by Jolie Wermter.</sub>
