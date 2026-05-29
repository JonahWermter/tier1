# Safety Protocols Reference

**Version:** 1.0
**Updated:** 2026-05-09

> **Loading Note:** This file is NOT automatically in context. SKILL.md must explicitly load it via
> the Read tool at session start. There is no `references:` frontmatter field in Claude Code SKILL.md.
> See SKILL.md Session Start section for the exact Read tool call.

---

## Tier Classification

Every proposed fix must be classified before presenting an approval gate.

### Tier 1: Safe to Execute

Reversible at any time. No rollback artifact required before execution.

**Characteristics:**
- Read-only diagnostic operations
- Non-destructive data collection
- Operations that do not modify system state

**Examples:**
- Reading registry values (`Get-ItemProperty`, `reg query`)
- Exporting registry keys for inspection (`reg export` to a temp file — read path only)
- Checking service status (`Get-Service`, `sc.exe qc`)
- Examining event logs (`Get-EventLog`, `Get-WinEvent`)
- Running `sfc /scannow` (scan only, no repair)
- Checking disk usage (`Get-PSDrive`, `Get-Volume`)
- Listing installed programs (`Get-ItemProperty HKLM:\...Uninstall\*`)
- Collecting process list (`Get-Process`)

**Approval gate:** Present as normal — user approves before execution. No restore point check required.

---

### Tier 2: Requires Verified Rollback Artifact

Modifies system state. A verified rollback artifact MUST exist before the approval gate is presented.

**Characteristics:**
- Writes to registry (non-CurrentControlSet)
- Modifies system files or services
- Changes startup entries or scheduled tasks
- Deletes or moves files in system directories

**Examples:**
- Modifying registry values (`Set-ItemProperty`, `reg add`)
- Stopping or starting services (`Stop-Service`, `Start-Service`, `sc.exe config`)
- Modifying system files (`Copy-Item` to replace a file, `icacls` permission changes)
- Clearing Windows Update cache (`net stop wuauserv` + cache deletion)
- Running DISM repairs (`DISM /Online /Cleanup-Image /RestoreHealth`)
- Running `sfc /scannow /offwindir` (repair mode)
- Modifying hosts file
- Deleting or modifying startup registry entries (`HKCU:\Software\Microsoft\Windows\CurrentVersion\Run`)

**Rollback artifact requirement:**
- A System Restore point must exist (verified by check-rollback.ps1)
- PLUS a targeted rollback artifact for the specific change:
  - Registry: `reg export <key> <backup.reg>` before modification
  - Service config: `sc.exe qc <service>` output saved before change
  - File: `Copy-Item <source> <timestamped-backup-path>` before modification

**Approval gate:** Hard stop if rollback infrastructure is absent or broken — see check-rollback.ps1 for exact behavior.

---

### Tier 3: Refused Operations

The skill refuses to execute these operations regardless of user confirmation. No approval gate is shown. The refusal message tells the user what to tell a professional technician.

**Refusal response template lives in SKILL.md (UX layer).** This reference provides only the operation-specific content (name, commands, reason) — no UX copy here.

See: **Hard Limits** section below.

---

## Hard Limits (Tier 3 Operations)

Each entry is a Tier 3 operation. The skill refuses these regardless of user confirmation.

### BCD / Boot Configuration

**Exact Commands:** `bcdedit.exe`, `bcdboot.exe`, `bootrec.exe`, `bcdedit /set`, `bcdedit /delete`, `bcdedit /create`
**Trigger Patterns:** "edit boot settings", "fix bootloader", "change boot order", "repair boot configuration", "modify BCD", "boot manager", "BOOTMGR", "rebuild BCD store"
**Reason:** Boot configuration edits can render Windows unbootable with no in-session recovery path. Recovery requires Windows installation media and technician-level expertise. Risk of total system loss exceeds the scope of this tool.

---

### Diskpart on Existing Volumes

**Exact Commands:** `diskpart` with `format`, `delete partition`, `delete volume`, `clean`, `convert gpt`, `convert mbr` (any destructive diskpart verb on a volume that already has data)
**Trigger Patterns:** "format drive", "delete partition", "wipe disk", "repartition", "convert MBR to GPT", "convert GPT to MBR", "rebuild partition table", "diskpart clean"
**Reason:** Destructive diskpart operations on existing volumes cause permanent data loss. Even with a restore point, diskpart changes to the partition table are not recovered by System Restore. Risk is irreversible.

---

### Disabling Windows Defender

**Exact Commands:** `Set-MpPreference -DisableRealtimeMonitoring $true`, `Set-MpPreference -DisableBehaviorMonitoring $true`, disabling `WinDefend` service, `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender DisableAntiSpyware` registry write, `reg add ... /v DisableAntiSpyware /d 1`
**Trigger Patterns:** "disable antivirus", "turn off Defender", "disable real-time protection", "disable Windows Security", "disable Defender permanently", "add Defender exclusion" (the exclusion itself is acceptable — disabling entirely is not)
**Reason:** Disabling Defender removes the primary security layer and is a common malware evasion technique. This tool will never be used to weaken security posture, regardless of stated justification.

---

### HKLM\SYSTEM\CurrentControlSet Writes

**Exact Commands:** `reg add HKLM\SYSTEM\CurrentControlSet\...`, `Set-ItemProperty HKLM:\SYSTEM\CurrentControlSet\...`, direct writes to `HKLM:\SYSTEM\CurrentControlSet\Services\*`, `HKLM:\SYSTEM\CurrentControlSet\Control\*`
**Trigger Patterns:** "modify driver settings", "change service configuration in registry", "edit CurrentControlSet", "disable driver", "force service to manual in registry"
**Reason:** CurrentControlSet is the active control set used by the running kernel. Direct writes affect the live system without a safety net. Service configuration changes belong in the Services API (`sc.exe config`), which is Tier 2. Direct CurrentControlSet edits bypass that safety layer.
**Exception:** `sc.exe config <service> start= disabled` (service API path, not direct registry) is Tier 2, not Tier 3.

---

### Third-Party Registry Cleaners

**Exact Commands:** Any invocation of CCleaner, Registry Mechanic, Wise Registry Cleaner, RegCleaner, Advanced SystemCare (registry module), or any tool whose primary function is automated registry "cleaning"
**Trigger Patterns:** "run registry cleaner", "clean the registry", "fix registry errors automatically", "use CCleaner", "optimize registry", "remove invalid registry entries"
**Reason:** Registry cleaners delete entries heuristically, cannot distinguish orphaned keys from keys used by features not yet loaded, and have documented cases of breaking Windows and applications. No reputable Microsoft guidance recommends them. The cure is reliably worse than the disease.

---

### Execution Policy Weakening (Machine Scope)

**Exact Commands:** `Set-ExecutionPolicy Unrestricted -Scope MachinePolicy`, `Set-ExecutionPolicy Bypass -Scope MachinePolicy`, any Group Policy-level execution policy removal, registry writes to `HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell ExecutionPolicy`
**Trigger Patterns:** "disable PowerShell restrictions system-wide", "allow all scripts to run", "bypass execution policy for all users", "remove PowerShell security"
**Reason:** Machine-scope execution policy changes affect all users and all sessions. This is a system-wide security posture change, not a troubleshooting step. User-scope or Process-scope adjustments for a specific script are Tier 2, not Tier 3.

---

### UAC Level Reduction Below Default

**Exact Commands:** `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System ConsentPromptBehaviorAdmin` set to `0` (never notify), registry writes that disable UAC prompting
**Trigger Patterns:** "disable UAC", "turn off User Account Control", "never ask for permission", "disable admin prompts permanently", "make UAC stop appearing"
**Reason:** Disabling or bypassing UAC removes a core Windows security boundary. This weakens the system against privilege escalation attacks and is not a valid troubleshooting step for any problem this tool addresses.

---

## Confidence Tier Criteria

Every proposed fix carries a confidence tier — displayed as a dedicated block before the approval gate.

### Display Format (D-11)

```
**Confidence: HIGH** | Pattern match confirmed. Windows 11 Pro — compatible.
```

```
**Confidence: MEDIUM** | Named pattern found, but Windows version match is uncertain. Proceed with caution.
```

```
**Confidence: LOW** | General advice only — no pattern match for your Windows version. Proceed cautiously or escalate to a technician.
```

### Tier Definitions

**HIGH** — All three conditions must be met:
1. A named fix pattern in the relevant domain reference file matches the user's problem description
2. Windows version and edition match confirmed (via detect-version.ps1 output)
3. For application-layer issues specifically: Application event log entries confirm the failure pattern (e.g., Event ID 1000 in the Application log confirms a DLL failure).
   **For non-application-layer issues (networking, BSOD, services), condition 3 is automatically satisfied if conditions 1 and 2 are met.**

**MEDIUM** — One or more conditions apply:
- A named fix pattern exists, but Windows version match is uncertain or unconfirmed
- Diagnostic data collected, but no confirming log entries for the specific failure
- Fix is general advice that applies broadly without a specific pattern match

**LOW** — Apply when:
- No named pattern matches the user's reported problem
- Fix is general troubleshooting advice with unclear applicability
- Confidence cannot be established from available diagnostic data

**LOW behavior (D-10):** LOW confidence fixes ARE shown to the user — they are not refused. Present the fix with a prominent warning block AND the escape hatch commands (exact commands the user can run manually). Show a modified approval gate: "Run anyway / Show me what to tell a technician." User retains full agency.

### One-Way Elevation Rule (D-12)

Domain reference files pre-assign a **default confidence tier** for each fix pattern. Runtime diagnostic evidence can **elevate** the tier (MEDIUM → HIGH). Runtime cannot **lower** a tier below the domain reference's default floor.

When runtime elevation occurs, the reason must be shown (D-13):
```
Confidence elevated to HIGH — Application log (Event 1000) confirms the DLL failure matches this pattern.
```

### S Mode Constraint

On Windows S Mode machines (detected via `isSMode: true` in detect-version.ps1 output):
- Unsigned PowerShell scripts cannot execute (`check-rollback.ps1`, `detect-version.ps1` may be blocked)
- Any fix that requires running a .ps1 script must be downgraded to LOW confidence
- The escape hatch must show manual equivalents of any blocked scripts
- SKILL.md (Phase 2) must check `isSMode` before invoking any .ps1 file

---

## Version Compatibility Reference

Use `detect-version.ps1` output to validate fixes before presenting them. Key fields:

| Field | Values | Use For |
|-------|---------|---------|
| `isWin10` | true/false | Win10-specific fix gating |
| `isWin11` | true/false | Win11-specific fix gating |
| `isSMode` | true/false | Block script execution on S Mode |
| `isLTSC` | true/false | LTSC-specific fix gating (Group Policy, update behavior) |
| `isHome` | true/false | Home edition limitations (no Group Policy, no Hyper-V) |
| `isPro` | true/false | Pro edition features available |
| `osArchitecture` | "64-bit" / "ARM 64-bit" / "32-bit" | Architecture compatibility gating; "32-bit" should block most fix patterns and escalate |
| `executionPolicy` | string | Verify script execution is permitted before invoking .ps1 |

**Fix rejection rule (SAFE-03):** If a proposed fix is incompatible with the detected edition, reject it before presenting it to the user. Do not show a fix and then note the incompatibility — reject it upstream.

---

## Rollback Artifact Patterns

For Tier 2 operations, create a targeted rollback artifact using the pattern appropriate to the change type:

### Registry Key Backup
```powershell
reg export "HKLM\Software\Example\Key" "$env:TEMP\tier1-backup-$(Get-Date -f yyyyMMdd-HHmmss).reg"
```

### File Backup
```powershell
Copy-Item -Path $sourceFile -Destination "$env:TEMP\tier1-backup-$(Get-Date -f yyyyMMdd-HHmmss)-$(Split-Path $sourceFile -Leaf)" -Force
```

### Service Configuration Capture
```powershell
sc.exe qc $serviceName | Out-File "$env:TEMP\tier1-svcconfig-$(Get-Date -f yyyyMMdd-HHmmss)-$serviceName.txt"
```

---

*This file is a Phase 1 output. It is consumed by SKILL.md (Phase 2) and all domain reference files (Phases 3–4).*
*Do not add UX copy (refusal messages, approval gate text) to this file — those belong in SKILL.md.*
