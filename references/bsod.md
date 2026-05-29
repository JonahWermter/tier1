# BSOD Domain Reference

**Version:** 1.0
**Updated:** 2026-05-20

> **Loading Note:** This file is NOT automatically in context. SKILL.md must explicitly load it via
> the Read tool at session start. There is no `references:` frontmatter field in Claude Code SKILL.md.
> See SKILL.md Session Start section for the exact Read tool call.

---

## Diagnostic Methodology

Mental model behind the 3 worked examples below. Use it when evidence doesn't cleanly match a named section; use the worked examples when it does.

### Primary data source

Event ID 1001 (BugCheck) from the Windows System event log. Provider: Microsoft-Windows-WER-SystemErrorReporting. Contains the stop code and all parameters for every BSOD that occurred while Windows was running. This is the authoritative source.

NOT used: minidump (.dmp) files, WinDbg, DUMPCHK.exe. PowerShell 5.1 cannot parse binary dump files. Event log approach is equally reliable for stop code extraction and does not require additional tools.

### Supplementary data source

CrashControl registry key: `HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl` — `LastBugcheckCode` key (ASSUMED — soft-fail required; key may not exist on all systems or before a BSOD has occurred). Treat as corroborating evidence only. Diagnosis must not depend on registry key existence.

### Pattern detection (D-B5)

Query Event ID 1001 history (last 10–20 entries) before diagnosing root cause:

- **Same stop code recurring (3+ events):** Persistent issue. Elevate confidence to HIGH. Root cause is specific and repeatable.
- **Mixed stop codes across events:** System instability. Broaden diagnosis — do not focus on a single code. Check RAM, storage, and recently changed drivers before proposing a focused fix.
- **Single event:** Possibly transient. Default confidence MEDIUM. Propose the appropriate fix but recommend monitoring for recurrence.

### Evidence-collection priorities

1. Event ID 1001 history (last 10–20 entries) — stop codes, timestamps, faulting module names if present
2. CrashControl registry read (supplementary, soft-fail)
3. Recently changed or installed drivers — Get-WinEvent for Event ID 7036/7045 referencing driver changes
4. System file integrity state — relevant if no driver identified (D-B4 cascade path)

### Tier discipline

| Operation | Tier | Rationale |
|-----------|------|-----------|
| `Get-WinEvent` (Event ID 1001 query) | Tier 1 | Read-only event log access |
| `Get-ItemProperty` CrashControl registry | Tier 1 | READ only — Tier 3 hard limit covers WRITES to CurrentControlSet, not reads |
| Driver update/rollback via `pnputil` | Tier 2 | Modifies driver state; rollback pre-check required |
| SFC/DISM cascade (D-B4 path) | Tier 1/2 | Follows two-gate pattern from windows-general.md |
| BCD edits (bcdedit, bcdboot, bootrec) | **Tier 3 — REFUSED** | See 0x0000007B section and safety-protocols.md Hard Limits |

### Research subagent trigger

When the stop code is NOT in the hardcoded table below, apply the Research Subagent pattern (defined in SKILL.md). Pass to the reasoning pattern: stop code value, Event 1001 full message text, system snapshot ($ver output), user-described symptoms.

Return D-C4 schema:
```
{
  confidence: HIGH | MEDIUM | LOW,
  key_findings: ["finding 1", "finding 2", ...],
  recommended_action: "specific next step",
  caveats: ["caveat 1", ...],
  sources_quality: "description of knowledge basis"
}
```

Synthesis rule (D-B3): weight research output equally with table results. Do NOT auto-downgrade confidence because a code wasn't in the table. A strong research finding at HIGH confidence is valid. Confidence flows from research quality, not from table membership.

### Two-gate sequencing

When D-B4 cascade is reached (driver-identified path exhausted, no driver identified): follow the SFC → DISM two-gate pattern from windows-general.md. Never bundle.

---

## Stop Code Reference Table

Hardcoded lookup table for the top ~20 common stop codes. Match the stop code extracted from Event ID 1001 against this table. Unknown codes (not listed here) → invoke research subagent pattern.

| Code | Mnemonic | Plain-English Cause | Primary Fix Path |
|------|----------|---------------------|-----------------|
| 0x0000000A | IRQL_NOT_LESS_OR_EQUAL | Driver accessed memory at the wrong interrupt priority level — typically a bad or outdated driver | Update or roll back the most recently changed driver; check driverList for recent changes |
| 0x000000D1 | DRIVER_IRQL_NOT_LESS_OR_EQUAL | Same cause as 0xA but more specific to network/storage drivers — most frequently occurring BSOD type | Update or roll back recent driver; check Event 1001 parameters for faulting module name |
| 0x0000001E | KMODE_EXCEPTION_NOT_HANDLED | Kernel-mode exception that nothing caught — driver or hardware incompatibility | Update drivers; check Event 1001 parameters for specific module name |
| 0x00000050 | PAGE_FAULT_IN_NONPAGED_AREA | Memory access violation in non-pageable memory — faulty RAM, corrupt driver, or disk corruption | Run SFC first; if no improvement, test RAM with `mdsched.exe` |
| 0x0000007E | SYSTEM_THREAD_EXCEPTION_NOT_HANDLED | System thread threw an exception that wasn't caught — driver or hardware | Update or roll back the driver named in stop code parameters |
| 0x0000007F | UNEXPECTED_KERNEL_MODE_TRAP | CPU trap not caught by the kernel — usually a hardware fault or overclocking instability | Suspected hardware; escalate to technician if it persists after removing overclocking |
| 0x0000009F | DRIVER_POWER_STATE_FAILURE | Driver did not respond correctly during sleep/wake power transition | Update the driver responsible for power management; check Event 1001 for device name |
| 0x000000C4 | DRIVER_VERIFIER_DETECTED_VIOLATION | Windows Driver Verifier caught a driver writing outside its bounds | Identify violating driver from Event 1001 parameters; update or uninstall |
| 0x0000003B | SYSTEM_SERVICE_EXCEPTION | Exception thrown inside a system service or driver during a system call | Update all drivers; check for recently installed software |
| 0x0000004E | PFN_LIST_CORRUPT | Page Frame Number list is corrupt — bad RAM or a misbehaving driver | Test RAM with `mdsched.exe`; run SFC to rule out file corruption |
| 0x0000001A | MEMORY_MANAGEMENT | Severe memory management error — bad RAM, bad driver, or corrupted system files | Test RAM with `mdsched.exe`; update drivers; run SFC if RAM tests clean |
| 0x000000EF | CRITICAL_PROCESS_DIED | A critical Windows process (csrss, lsass, winlogon, etc.) exited unexpectedly | Run SFC/DISM; check Event 1001 for which process name was cited |
| 0x00000133 | DPC_WATCHDOG_VIOLATION | A deferred procedure call (DPC) ran too long — driver bug or SSD firmware issue | Update drivers and SSD firmware; check for driver conflicts |
| 0x00000139 | KERNEL_SECURITY_CHECK_FAILURE | Kernel detected data structure corruption — a bad driver corrupted kernel memory | Update or roll back recently changed drivers; check Event 1001 for driver name |
| **0x0000007B** | **INACCESSIBLE_BOOT_DEVICE** | **Boot device was not accessible at startup — storage driver or BIOS config issue** | **TIER 3 ESCALATION — see 0x0000007B section below. No fix commands. No approval gate.** |
| 0x000000D8 | DRIVER_USED_EXCESSIVE_PTES | A driver consumed too many page table entries — driver memory leak | Identify the driver from Event 1001; update or uninstall |
| 0x00000116 | VIDEO_TDR_FAILURE | GPU driver crashed and Windows could not recover the display | Update GPU driver; check GPU temperature; roll back driver if update just occurred |
| 0x00000124 | WHEA_UNCORRECTABLE_ERROR | Hardware error logged by Windows Hardware Error Architecture — CPU, RAM, or motherboard | Check WHEA event log; hardware-suspected; escalate if error recurs |
| 0x0000000E | NO_USER_MODE_CONTEXT | Kernel-mode access violation while switching to user mode — hardware or driver | Update all drivers; suspected hardware if driver updates don't help |
| 0xC0000005 | ACCESS_VIOLATION | Memory access violation — can occur in both user and kernel context | Depends on context; if boot-blocking, treat as Tier 3 escalation |

---

## Known Stop Code

**What this covers:** User reports a BSOD with a stop code that matches an entry in the Stop Code Reference Table above. Includes cases where the stop code is extracted from Event ID 1001 or provided directly by the user from the BSOD screen.

**Trigger conditions:**
- Event ID 1001 history contains a stop code matching one of the table entries (excluding 0x0000007B, which routes immediately to the Tier 3 Escalation section)
- User description names or pastes a stop code and it matches a table entry

**Diagnosis logic (apply to collected data):**
1. Extract stop code from Event 1001 history ($bsodEvents). If user provided the code directly, use that.
2. Look up the code in the Stop Code Reference Table. Identify the Primary Fix Path column.
3. Check Event 1001 message parameters for a faulting module name (e.g., "nvlddmkm.sys", "tcpip.sys"). If present, the module name is a higher-signal routing indicator than the code alone.
4. Apply pattern detection per D-B5: count how many times this same code appears in the Event 1001 history.
   - 3+ occurrences of the same code: recurring pattern → elevate confidence to HIGH
   - Mixed codes: system instability → broaden diagnosis; do not focus on one code
   - Single occurrence: possibly transient → MEDIUM confidence; monitor recommendation
5. If faulting module name is present AND matches a known driver (GPU, network, storage): route directly to the Driver-Identified BSOD section — it provides more targeted diagnosis.
6. If no faulting module name: use the Primary Fix Path from the table. Most common path is driver update/rollback.

**Default confidence tier:** MEDIUM (named stop code match; recurring same code or confirming faulting module name elevates to HIGH)
**Runtime elevation rule:** If the same stop code appears 3+ times in Event ID 1001 history AND $ver.isWin10 = true OR $ver.isWin11 = true (supported client OS confirmed): elevate to HIGH. State reason per D-13.

**Fix classification:** Tier 2 — driver update or rollback modifies driver state. Rollback pre-check via check-rollback.ps1 required before approval gate. SFC (if cascade reached) is Tier 1; DISM (if cascade reached) is Tier 2.

**Rollback plan text (for approval gate):**
```
Rollback plan:
- System Restore point: [mostRecentDate] ([pointAge_days] days ago). To use: Settings → Update & Security → Recovery → Open System Restore → choose this point.
- Driver rollback: if this fix involves a driver update, the previous driver version can be restored via Device Manager → right-click device → Properties → Driver tab → Roll Back Driver. The current driver version will be noted before any update is applied.
- If driver rollback via Device Manager is not available (greyed out): the System Restore point above covers the driver state.
```

**Change diff text (for approval gate, D-06 format):**
```
What changes: The driver associated with the stop code will be updated (or rolled back if recently updated). This replaces the driver binary on disk and registers the new version with Windows.

Exact paths/keys/services: Driver binary in %SystemRoot%\System32\drivers\; device entry in Device Manager; associated registry entries under HKLM\SYSTEM\CurrentControlSet\Services\[driver name]

Time estimate: 2–5 minutes

Restart required: Yes — driver changes require a reboot to take effect.
```

**Fix commands (canonical — escape hatch must match exactly):**
```
# Step A: Record current driver version before any change (rollback documentation)
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Get-WmiObject Win32_PnPSignedDriver | Where-Object {$_.DeviceName -like '*[DeviceType]*'} | Select-Object DeviceName, DriverVersion, DriverDate | ConvertTo-Json"

# Step B: Update driver (Device Manager path — safest approach; no silent install risk)
# Instruct user: open Device Manager → find the device associated with [driver name] → right-click → Update driver → Search automatically for drivers
# OR for GPU (NVIDIA example):
# Download latest driver from manufacturer site and install with clean install option

# Step C: Driver rollback (if driver was recently updated and stop codes started after the update)
# Instruct user: Device Manager → right-click device → Properties → Driver tab → Roll Back Driver
```
Substitute [DeviceType] with the device category identified from Event 1001 faulting module (e.g., "Display", "Network", "Storage").

**Post-verification check:**
```
# After reboot, check for new Event ID 1001 entries:
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Get-WinEvent -LogName System -MaxEvents 50 -ErrorAction SilentlyContinue | Where-Object {$_.Id -eq 1001 -and $_.ProviderName -like '*WER*'} | Select-Object TimeCreated, Message | ConvertTo-Json"
```
Success: no new Event ID 1001 entries with the same stop code after the driver change. Monitor for 24–48 hours for recurring BSOD.

**Post-fix explanation text (for UX-04):**
```
What was wrong: Your system crashed with a [stop code mnemonic] stop code. In plain English: [insert plain-English cause from Stop Code Reference Table]. This specific stop code indicates [explanation of what the code means mechanically].

Why it happened: [cause column explanation from table, adapted to user's specific driver/device if identified]. BSOD stop codes are Windows' way of halting the system before a bad driver or hardware condition causes data corruption.

What changed: The [driver name] driver was [updated/rolled back]. The new version replaces the file that was causing Windows to crash.

Why the fix worked: The driver change removes the specific code path that was triggering the kernel-level exception. If the new driver version is stable, the system will complete its operations without halting.

If something seems off later: Your System Restore point from [mostRecentDate] is your safety net. If BSODs return with the same or a different stop code, check Event ID 1001 again for new entries and note whether the code has changed — a changed code after a driver update suggests the fix addressed one issue but another remains.
```

---

## Unknown Stop Code

**What this covers:** Stop code extracted from Event ID 1001 does NOT appear in the Stop Code Reference Table above. The code is real — it occurred — but it is not in the hardcoded top-20 list.

**Trigger conditions:**
- Event ID 1001 history contains a stop code that does not match any entry in the table
- User provides or describes a stop code not found in the table

**Diagnosis logic (apply to collected data):**
1. Confirm the stop code is correctly read from Event ID 1001 (not a user transcription error — hex codes starting with 0x, 8 characters total).
2. Check 0x0000007B specifically — if present, route immediately to the 0x7B Tier 3 Escalation section regardless of table membership.
3. Apply the Research Subagent pattern with D-C4 schema. Pass: stop code value, full Event 1001 message text, system snapshot ($ver output), user symptoms, any faulting module name from Event 1001 parameters.
4. Synthesize research output:
   - Use confidence from research result — do NOT force MEDIUM because code isn't in table (D-B3)
   - If research identifies a known driver or software cause: route to driver update/rollback fix path (Tier 2)
   - If research suggests hardware: note hardware-suspected in diagnosis; recommend monitoring and escalation if BSOD recurs
   - If research is uncertain: recommend monitoring + SFC as a safe first diagnostic step
5. Apply pattern detection per D-B5 regardless of whether the code is known.

**Default confidence tier:** Determined by research output — do NOT auto-assign MEDIUM. Research finding at HIGH confidence is valid (D-B3). If research is inconclusive: MEDIUM with explicit uncertainty language.
**Runtime elevation rule:** If research output returns confidence: HIGH AND $ver.isWin10 = true OR $ver.isWin11 = true AND Event 1001 contains a faulting module name: elevate to HIGH. State reason per D-13.

**Fix classification:** Determined by research output. If research identifies a driver fix: Tier 2 (same as Known Stop Code). If research recommends SFC first: Tier 1, then Tier 2 DISM gate if needed. If research is uncertain: Tier 1 diagnostic only (read-only SFC scan or event log review — no state modification without a clearer diagnosis).

**Rollback plan text (for approval gate):**
```
Rollback plan:
- System Restore point: [mostRecentDate] ([pointAge_days] days ago). To use: Settings → Update & Security → Recovery → Open System Restore → choose this point.
- Specific rollback artifact depends on the fix path identified by research: driver rollback (see Known Stop Code section rollback plan), or SFC/DISM rollback plans (see windows-general.md SFC/DISM section).
```

**Change diff text (for approval gate, D-06 format):**
```
What changes: [determined by research output — fill in specific fix path identified]

Exact paths/keys/services: [determined by research output]

Time estimate: [determined by fix type — driver change: 2–5 minutes; SFC: 10–20 minutes]

Restart required: [Yes for driver changes; No for SFC alone]
```

**Fix commands (canonical — escape hatch must match exactly):**
```
# Fix commands are determined by research subagent output.
# If research identifies a driver fix: use Driver-Identified BSOD fix commands (see that section).
# If research recommends SFC/DISM: use windows-general.md SFC/DISM/chkdsk Repair fix commands.
# If research is uncertain: run read-only SFC scan first (Tier 1):
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "sfc /scannow"
```

**Post-verification check:**
```
# After fix: check for new Event ID 1001 entries with the same stop code:
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Get-WinEvent -LogName System -MaxEvents 50 -ErrorAction SilentlyContinue | Where-Object {$_.Id -eq 1001 -and $_.ProviderName -like '*WER*'} | Select-Object TimeCreated, Message | ConvertTo-Json"
```
Success: no new Event ID 1001 entries with the same stop code. If the code was transient (single event, no recurrence), monitoring is the primary next step.

**Post-fix explanation text (for UX-04):**
```
What was wrong: Your system crashed with stop code [code]. This code is not in the common list, so I researched it specifically. Based on that research: [key_findings from research subagent output, plain English].

Why it happened: [recommended_action context from research output]. [caveats from research output if relevant].

What changed: [fix action taken — driver updated, SFC run, etc.].

Why the fix worked: [mechanism from research output, adapted to the specific fix applied].

If something seems off later: Your System Restore point from [mostRecentDate] is your safety net. If BSODs return, check Event ID 1001 again — note whether the stop code has changed. A different code after a fix suggests the original cause was addressed but another issue is present.
```

---

## Driver-Identified BSOD

**What this covers:** Event ID 1001 message text or parameters name a specific faulting driver or module (e.g., "nvlddmkm.sys" for NVIDIA GPU, "atikmdag.sys" for AMD GPU, "tcpip.sys" for TCP/IP stack, "ntfs.sys" for NTFS driver). When a specific driver is named, diagnosis is more targeted than the Known Stop Code path.

**Trigger conditions:**
- Event ID 1001 message contains a faulting module name (a .sys or .dll filename in the message parameters)
- User reports BSOD that names a specific driver file on screen
- Any stop code where Event 1001 parameters include a driver binary name alongside the code

**Diagnosis logic (apply to collected data):**
1. Extract the faulting module name from the Event ID 1001 message text. Common format in the message: "The computer has rebooted from a bugcheck. The bugcheck was: [code]. [...] A dump was saved in: [path]. Report Id: [id]." — look for a driver name in the broader Event 1001 message or in the crash description.
2. Map the driver name to its device category:
   - `nvlddmkm.sys`, `nvkflt.sys` → NVIDIA GPU driver
   - `atikmdag.sys`, `amdkmdag.sys` → AMD GPU driver
   - `tcpip.sys` → TCP/IP networking stack
   - `ntfs.sys` → NTFS file system driver (consider chkdsk if ntfs.sys is named)
   - `storport.sys`, `iaStorA.sys`, `nvme.sys` → storage/NVMe controller driver
   - `ndis.sys` → network driver interface stack
   - Unknown .sys → search Event log for install date; check recently changed drivers
3. Check whether the driver was recently updated or installed. Query Event ID 7036/7045 from System log for driver install events around the time of the first BSOD.
4. If driver was recently updated and BSODs started after the update: high likelihood the update introduced the fault. Fix path: roll back the driver.
5. If driver has NOT been recently updated: fix path is to update to the latest version from the device manufacturer.
6. D-B4 fallback: if Event ID 1001 indicates a driver issue but does NOT name a specific module, broaden scope:
   - Check recently changed drivers across all device categories (query Event 7045 history)
   - If no recent driver changes found: cascade to SFC/DISM (follows two-gate pattern from windows-general.md). A driver-unspecified BSOD with no recent driver changes can indicate system file corruption.

**Default confidence tier:** HIGH (specific driver named in Event 1001 is a high-confidence signal)
**Runtime elevation rule:** If Event ID 1001 names a specific driver module AND the same driver name recurs across 2+ Event 1001 entries AND $ver.isWin10 = true OR $ver.isWin11 = true: confirmation of persistent driver fault — state reason per D-13. Confidence is HIGH at the default; this rule confirms it with additional evidence.

**Fix classification:** Tier 2 — driver update or rollback modifies driver state. Rollback pre-check via check-rollback.ps1 required before approval gate. If D-B4 cascade reaches SFC: Tier 1 first, then Tier 2 DISM gate only if SFC reports unable-to-fix string.

**Rollback plan text (for approval gate):**
```
Rollback plan:
- System Restore point: [mostRecentDate] ([pointAge_days] days ago). To use: Settings → Update & Security → Recovery → Open System Restore → choose this point.
- Driver rollback: if rolling back a driver, the current version is recorded before rollback. Device Manager → right-click device → Properties → Driver tab → Roll Back Driver can restore the version if rollback makes things worse.
- If rolling back the driver causes additional issues: the System Restore point above restores the full driver state as it was at [mostRecentDate].
```

**Change diff text (for approval gate, D-06 format):**
```
What changes: The [device category] driver ([driver filename]) will be [updated to the latest manufacturer version / rolled back to the previous version]. The driver binary on disk is replaced and the device re-initializes on the next boot.

Exact paths/keys/services: %SystemRoot%\System32\drivers\[driver filename]; device entry in Device Manager; HKLM\SYSTEM\CurrentControlSet\Services\[driver service name]

Time estimate: 3–10 minutes (includes download time for driver update; rollback is under 2 minutes)

Restart required: Yes — driver changes require a reboot to take effect.
```

**Fix commands (canonical — escape hatch must match exactly):**
```
# Step A: Record current driver version (rollback documentation)
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Get-WmiObject Win32_PnPSignedDriver | Where-Object {$_.InfName -like '*[driver name]*' -or $_.DeviceName -like '*[device type]*'} | Select-Object DeviceName, DriverVersion, DriverDate, InfName | ConvertTo-Json"

# Step B (if updating driver): Direct user to manufacturer download site
# NVIDIA GPU: https://www.nvidia.com/drivers
# AMD GPU: https://www.amd.com/en/support
# Intel: https://www.intel.com/content/www/us/en/download-center/home.html
# Generic: Device Manager → right-click device → Update driver → Search automatically

# Step B (if rolling back driver due to recent update causing BSODs):
# Device Manager → right-click [device name] → Properties → Driver tab → Roll Back Driver
# PowerShell equivalent for driver rollback (pnputil — Tier 2):
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "pnputil /rollback-driver [inf name]"

# D-B4 fallback: if no specific driver identified — check recent driver changes
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Get-WinEvent -LogName System -MaxEvents 50 -ErrorAction SilentlyContinue | Where-Object {$_.Id -eq 7045} | Select-Object TimeCreated, Message | ConvertTo-Json"
# If no recent driver changes found → cascade to SFC (see windows-general.md SFC/DISM section)
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "sfc /scannow"
```

**Post-verification check:**
```
# After reboot: check for new Event ID 1001 entries
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Get-WinEvent -LogName System -MaxEvents 50 -ErrorAction SilentlyContinue | Where-Object {$_.Id -eq 1001 -and $_.ProviderName -like '*WER*'} | Select-Object TimeCreated, Message | ConvertTo-Json"
```
Success: no new Event ID 1001 entries with the same stop code after the driver change. Monitor for recurrence — some driver-related BSODs take multiple boot cycles to manifest.

**Post-fix explanation text (for UX-04):**
```
What was wrong: Your system crashed because the [device category] driver ([driver filename]) caused a kernel-level fault. In plain English: [device category] handles [what the device does — e.g., "your graphics card, which renders everything you see on screen"]. When the driver that controls it crashes, Windows cannot safely continue and halts entirely to prevent data corruption.

Why it happened: [If recent update: "A recent driver update introduced a bug. The new version behaved in a way the Windows kernel didn't expect, triggering the stop code."] [If no recent update: "The driver version installed had a compatibility issue with your current Windows version, or the driver files became corrupt over time."]

What changed: The [device category] driver was [updated to version X / rolled back to the previous version]. The driver binary on disk was replaced with a version known to be stable.

Why the fix worked: Replacing the driver removes the specific code that was causing the crash. The kernel now has a driver version that handles [device category] operations without triggering a stop condition.

If something seems off later: Your System Restore point from [mostRecentDate] is your safety net. If the same stop code returns with the same driver file named, the hardware itself may be faulty — which is beyond what remote troubleshooting can resolve safely.
```

---

## 0x0000007B — Tier 3 Escalation

**THIS IS NOT A FIX SECTION. This is an explicit Tier 3 refusal. No fix commands. No approval gate. No rollback plan.**

**Trigger conditions:**
- Stop code 0x0000007B or 0x7B detected in Event ID 1001 history, user description, or CrashControl registry
- User describes "INACCESSIBLE_BOOT_DEVICE" stop code
- Any diagnosis path that leads to the conclusion that BCD edits (bcdedit, bcdboot, bootrec) are required

**Plain-English explanation (always deliver this to the user):**

This stop code — INACCESSIBLE_BOOT_DEVICE — means that Windows could not see its own hard drive (or SSD) during the startup process. The operating system is loaded from storage, and if the storage controller driver isn't ready at exactly the right point during boot, Windows cannot find its own files and stops completely.

**Common causes:**
- A Windows update changed the storage controller driver, and the new driver doesn't initialize fast enough on your hardware
- The BIOS setting for storage mode was changed (IDE, AHCI, RAID) after Windows was installed — Windows was configured for a different mode than what the BIOS now presents
- A failing hard drive or SSD that the storage controller can no longer see reliably
- Motherboard firmware update changed storage controller behavior

**Why this tool refuses to fix it:**

Resolving 0x0000007B typically requires editing the Windows Boot Configuration Data (BCD) using `bcdedit.exe`, `bcdboot.exe`, or `bootrec.exe`. These are Tier 3 hard-limit operations per safety-protocols.md. Boot configuration edits can render Windows completely unbootable with no recovery path within the same Windows session — recovery from a botched BCD edit requires Windows installation media and in-person access to the machine. This is beyond the scope of safe remote troubleshooting.

**What to tell a technician:**

Tell the technician the following:

"My computer cannot start. When it tries to boot, I get a blue screen with stop code 0x0000007B (INACCESSIBLE_BOOT_DEVICE). This usually means the storage driver is not loading correctly during boot, or the BIOS storage mode setting doesn't match what Windows expects. A technician will need to:

1. Boot from Windows installation media (a USB drive with Windows on it)
2. Use the recovery environment to check whether the BCD store is intact (`bootrec /fixbcd` or `bootrec /scanos`)
3. Verify the BIOS storage controller mode (AHCI, IDE, RAID) matches what Windows was originally installed with
4. If the storage mode changed, either restore the previous setting in BIOS or use safe mode boot to install the correct storage driver before normal boot
5. If the drive itself is failing, the data needs to be recovered before any repair attempt

The specific commands involved are `bcdedit.exe`, `bcdboot.exe`, and `bootrec.exe`, which require booting from external media and cannot be safely run from within a broken Windows session."

**Tier 3 refusal applies:** The skill will not issue bcdedit, bcdboot, or bootrec commands. The skill will not present an approval gate for these operations. The refusal is final regardless of user confirmation.

---

## DIAG-02 Targeted Collection

PowerShell 5.1 collection commands for the BSOD domain. Defined here per D-S4. Invoked by SKILL.md post-routing, silently, before the combined disclosure block.

Each command has a soft-fail rule: if the command fails or returns empty, set the corresponding variable to `""` and continue. Do not halt on collection failures. Do not add XPath filters — collect raw, filter during analysis.

```powershell
# 1. Event ID 1001 (BugCheck) history — PRIMARY source
# Provider: Microsoft-Windows-WER-SystemErrorReporting
$bsodEvents = Get-WinEvent -LogName System -MaxEvents 100 -ErrorAction SilentlyContinue |
    Where-Object {$_.Id -eq 1001 -and $_.ProviderName -like '*WER*'} |
    Select-Object TimeCreated, @{N='Message';E={$_.Message}} |
    ConvertTo-Json
if (-not $bsodEvents) { $bsodEvents = "" }

# 2. CrashControl registry — SUPPLEMENTARY (key name ASSUMED; soft-fail required)
$crashControl = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" `
    -ErrorAction SilentlyContinue |
    Select-Object LastBugcheckCode, LastCrashTime |
    ConvertTo-Json
if (-not $crashControl) { $crashControl = "" }

# 3. Recent driver install/change events — for D-B4 driver identification
$recentDriverChanges = Get-WinEvent -LogName System -MaxEvents 50 -ErrorAction SilentlyContinue |
    Where-Object {$_.Id -eq 7036 -or $_.Id -eq 7045} |
    Select-Object TimeCreated, Message |
    ConvertTo-Json
if (-not $recentDriverChanges) { $recentDriverChanges = "" }
```

---

*This file is a Phase 4 output. It is consumed by SKILL.md and governs routing, diagnosis, and fix proposals for the BSOD problem domain.*
*Do not add UX copy (approval gate text, escape hatch instructions, refusal message wording) to this file — those belong in SKILL.md.*
