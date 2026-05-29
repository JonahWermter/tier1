# Tier1

AI-guided Windows troubleshooting — structured, safe, transparent, and modular.

## Architecture

- One `SKILL.md` orchestrates: triage, domain routing, approval gate, post-fix explanation
- Domain knowledge in `references/` (windows-general, gaming-mods, outlook-m365, network, bsod)
- PowerShell safety scripts in `scripts/safety/`
- Domain agents in `.claude/agents/` (system, apps, network) with shared safety via `tier1-safety` skill
- PowerShell 5.1 floor (pre-installed on all Win10/11); no external dependencies

## Safety Non-Negotiables

These are hard constraints for all behavior:

1. **Tier 3 operations are refused, not warned.** BCD edits, diskpart on existing volumes, disabling Defender, HKLM\SYSTEM\CurrentControlSet writes — refused, period.
2. **Rollback must exist before execution.** Check `Get-ComputerRestorePoint` and VSS status before any Tier 2+ fix. Absent rollback = hard stop.
3. **Version detection before any fix path.** Windows edition (Home/Pro/LTSC/S Mode) and architecture (x64/Arm64) must be detected before any fix is proposed.
4. **One change set per approval gate.** Never bundle unrelated fixes. Each approval covers exactly one logical change.
5. **Rollback plan shown before the approval gate.** Not after. The user sees the undo path before they confirm.
