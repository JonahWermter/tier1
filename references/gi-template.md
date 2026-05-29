# Guided Implementation Template

**Version:** 1.0
**Updated:** 2026-05-26

> **NOT a runtime reference.** This file is NOT loaded at session start and is NOT a runtime reference for Claude. It is a specification document for content authors writing `## Guided Implementation` sections in domain reference files. Phase 8+ authors read this file to understand required fields, heading conventions, and the sequence gate pattern.

---

## GI Section Heading Convention

Every Guided Implementation section uses this exact heading format:

```markdown
## Guided Implementation: [Task Name]
```

The first field in every GI section is the GI-ID:

```
**GI-ID:** [domain-prefix]-[nn]
```

For example: `**GI-ID:** NETGI-01`

### Domain Prefix Assignment

| Domain Reference File | GI-ID Prefix |
|-----------------------|-------------|
| network.md | NETGI |
| windows-general.md | WGINGI |
| gaming-mods.md | GAMGI |
| outlook-m365.md | OUTGI |
| bsod.md | BSODGI |

The `nn` portion is a two-digit sequential number within the domain (01, 02, ...).

This convention enables the Phase 6 Status Arbiter to recognize GI sections as distinct from break-fix sections, and provides consistent cross-domain identification for traceability.

---

## GI Field Template

Every GI section must contain all 9 fields below. The field names are the canonical labels — use them verbatim so the Phase 6 Status Arbiter and auditors can locate them.

| # | Field Name | Description |
|---|-----------|-------------|
| 1 | **Trigger signals** | When to apply this GI section — user goal descriptions and context signals that route here. What the user says or means that indicates this guided implementation path, not a break-fix path. |
| 2 | **Environment discovery checklist** | What to ask or check before step 1: OS version, disk space, admin rights, network connectivity, prerequisites, conflicting existing configuration. This field replaces both the break-fix "Trigger conditions" and "Diagnosis logic" fields — GI has no diagnosis per se; discovery replaces it. |
| 3 | **Confidence tier** | The 2x2 matrix result for this scenario (see Confidence Matrix section below). State the assessed tier (HIGH / MEDIUM / LOW) and the two-axis rationale. |
| 4 | **Step classification** | Tier classification for each step in the implementation sequence. Format: "Step 1: Tier X — [description], Step 2: Tier Y — [description], ..." A user can evaluate risk at each step before the approval gate. |
| 5 | **Abort-and-cleanup plan** | Cumulative-state cleanup for partial completion in reverse-step order (see Sequence Gate Pattern section below). Which steps have persistent state changes and what the exact undo action is. Tier 1 steps need no cleanup entry. |
| 6 | **Change diff** | What changes: exact paths, registry keys, services, or settings affected; time estimate; whether restart is required. Identical format to break-fix change diff. |
| 7 | **Implementation commands** | The actual sequence of commands and/or UI steps to achieve the goal. Includes any conditional logic for OS edition or execution policy mode. |
| 8 | **Post-verification check** | How to confirm the goal was achieved after the sequence completes. Specific, observable criterion — not "it should work." |
| 9 | **Post-implementation explanation** | What was set up, why each step was needed, what to do if something seems off after the session. Plain English for a non-technical user. |

**Field count note:** Break-fix sections use 10 fields. GI sections use 9 fields because "Diagnosis logic" (break-fix field 3) merges into "Environment discovery checklist" (GI field 2). GI has no diagnosis per se — the checklist replaces it. The Phase 6 Status Arbiter treats a GI section as "Present" when all 9 GI fields are present.

---

## Confidence Matrix

GI confidence uses two axes: **procedure stability** and **environment compatibility**.

| | Environment Compatible | Environment Uncertain |
|---|---|---|
| **Procedure Stable** | HIGH | MEDIUM |
| **Procedure Uncertain** | MEDIUM | LOW |

**Axis definitions:**

- **Procedure stability:** The steps are documented, version-independent, and work consistently across the supported OS range. Steps that rely on undocumented behavior, change frequently between OS versions, or have known failure modes on specific editions are "uncertain."
- **Environment compatibility:** The target OS version, edition, and configuration support all steps without modification. S Mode, restricted execution policy, or missing prerequisites introduce uncertainty.

**Default MEDIUM when unsure** — if either axis is unclear, assign MEDIUM rather than attempting to justify HIGH.

**Distinction from break-fix confidence:** Break-fix confidence derives from pattern match quality and version match. GI confidence derives from procedure stability and environment compatibility. They use the same HIGH / MEDIUM / LOW labels but are assessed on different axes.

---

## Sequence Gate Pattern

Every GI section implements this three-part flow. Sub-agents follow this pattern when executing a GI section.

### Pre-flight (before Step 1)

Show the complete implementation plan upfront, before any step begins. Content:

- Step count (N steps total)
- Each step's purpose in one line
- Total estimated time
- What "abort at any point" means for state cleanup

Example:

> "Here's what we'll do (3 steps):
> - Step 1 — Open sharing settings (read-only, 30 seconds)
> - Step 2 — Configure folder permissions (Tier 2, creates restore point first)
> - Step 3 — Enable SMB discovery (Tier 2, ~1 minute)
>
> If you want to stop after any step, I'll show you the cleanup for what was already changed."

The pre-flight shows trust and transparency — the user knows what they're agreeing to before the first gate.

### Per-step gate

Each discrete system change gets its own approval gate. Gate granularity rule: one gate per discrete change; consolidate only trivially-coupled steps (e.g., create a folder + immediately set its permissions in the same command); err toward more gates when in doubt (D-11).

**Gate block order (D-05 — do not reorder):**

```
---
**Abort-and-cleanup plan:**
If you want to stop after this step, here's how to undo what will be changed:
- [List each completed step in reverse order with exact undo command/action]
- [Steps that are Tier 1 (no persistent state): "Step N — nothing to undo (read-only)"]

[Change diff: what will change, exact paths/keys/services/settings, time estimate, restart required]

**Confidence: [HIGH / MEDIUM / LOW]** | [reason — procedure stability and environment compatibility basis]

How would you like to proceed?
- **Approve** — I'll walk you through this step
- **Skip this step** — Move on without this change
- **I'll do this myself** — Show me the commands to run manually
---
```

UX-06 (one change set per approval gate) applies to GI sequences exactly as it does to break-fix sequences.

### Abort-and-cleanup path

When a user stops mid-sequence after step K of N steps:

1. List which steps completed (steps 1 through K).
2. For each completed step in reverse order (step K, then K-1, ..., then 1): show the exact undo command or UI action.
3. This is **NOT** symmetric rollback — not every step has a registry artifact or file backup. Some steps have no persistent state.
4. UI-based steps may require manual reversal — show the exact UI path (Settings > ... > ...).
5. A step that was Tier 1 (no persistent state change) needs no cleanup entry.
6. State at abort = known-clean state for the completed subset.

Example cleanup block:

> "You completed Steps 1-2. To undo:
> - Step 2 cleanup — [exact command or Settings path to reverse the permission change]
> - Step 1 cleanup — nothing to undo (read-only, no state changed)
>
> Your system is back to its state before you started."

---

## Audit Recognition

The Phase 6 Status Arbiter recognizes GI sections as "Present" when all 9 adapted fields are present using the GI field names:

- Trigger signals
- Environment discovery checklist
- Confidence tier
- Step classification
- Abort-and-cleanup plan
- Change diff
- Implementation commands
- Post-verification check
- Post-implementation explanation

Auditors checking coverage of GI sections use these GI field names, not the break-fix field names (trigger conditions, diagnosis logic, fix commands, etc.). A GI section with all 9 GI fields counts as "Present" — equivalent to a fully-covered break-fix section.

Domain reference files that contain one or more GI sections under a `## Guided Implementation` block are considered to have GI coverage for audit purposes.
