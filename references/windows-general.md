# General Windows Domain Reference

**Version:** 1.0
**Updated:** 2026-05-10

> **Loading Note:** This file is NOT automatically in context. SKILL.md must explicitly load it via
> the Read tool at session start. There is no `references:` frontmatter field in Claude Code SKILL.md.
> See SKILL.md Session Start section for the exact Read tool call.

---

## Diagnostic Methodology

This section is the mental model behind the 4 worked examples below. Use it when evidence doesn't cleanly match a named section, and use the worked examples when it does.

### When evidence matches a worked example

Match the collected data to a section using the routing priority from SKILL.md Step 3b. When a match is found:
1. Apply the section's diagnosis logic against the collected variables ($stoppedServices, $systemEvents, $appEvents, $topProcesses, $diskSpace, $driverList, $hardwareFaultEvents).
2. Use the section's **default confidence tier** as the floor.
3. Apply the section's **runtime elevation rule** — if conditions are met, elevate to HIGH and state the reason per D-13.
4. Present the fix classification, rollback plan, and change diff exactly as documented in the section.

The worked examples are a senior T1 engineer's mental model written down: when the evidence matches, apply the recipe. The match must come from data, not from user description alone — description is a secondary routing signal.

### When no worked example matches (D-RT3)

When collected data does not cleanly match any of the 4 sections, do NOT refuse and do NOT escalate prematurely. Apply the methodology with explicit confidence uncertainty:

> "I don't see a clear pattern match for your exact problem, but here's how I'd approach it based on the evidence..."

Steps for unmatched problems:
1. State which signals you have (what's in $stoppedServices, $appEvents, $systemEvents, $hardwareFaultEvents) and which signals are absent.
2. Assign MEDIUM confidence if one or more signals point at a plausible cause; LOW if signals are ambiguous or absent.
3. Propose the most conservative fix consistent with the evidence — prefer read-only diagnostics (Event Viewer review, sfc /scannow) over state-modifying operations.
4. If no safe fix path exists, tell the user what to tell a technician: describe the observed signals, the event IDs, and the symptom.

The goal is informed forward progress, not paralysis. MEDIUM confidence with a Tier 1 diagnostic step is always better than refusing to engage.

### Evidence-collection priorities

For General Windows problems, these signals matter most:

- **$appEvents Event 1000 with Faulting Module Name** — the primary routing signal for DLL/runtime failures. The "Faulting Module Name" field in Event 1000 names the specific DLL. This is a high-confidence signal when present.
- **$systemEvents Event 7031 / Event 7034** — unexpected service termination. These are the correct fault signals for service failures. Event 7031 includes restart action details; 7034 is the simpler form. Both indicate a service stopped when it should not have.
- **$stoppedServices with StartType = Automatic in Stopped state** — services that are configured to start automatically but are currently stopped. This is the primary runtime signal; event 7031/7034 confirms the cause.
- **$hardwareFaultEvents: Kernel-Power Event 41, EventLog Event 6008, WHEA-Logger Events 1/17/18** — hardware-adjacent fault signals. Event 41 indicates the system rebooted without a clean shutdown (crash, power loss, or hardware instability). Event 6008 confirms a dirty/unexpected shutdown on the previous boot. WHEA-Logger events indicate hardware-layer errors detected by the WHEA (Windows Hardware Error Architecture).

**Important:** Event 7036 is NOT a fault signal. It fires on every service start and stop, including completely normal ones. It is a status-change notification, not a termination indicator. Filtering routing logic on Event 7036 floods the signal with noise — use 7031 and 7034 instead.

### Tier discipline

Before any fix proposal, apply the correct tier classification:

| Operation | Tier | Rationale |
|-----------|------|-----------|
| `sfc /scannow` | Tier 1 | Reads from the side-by-side store; no net system state change |
| DISM /RestoreHealth | Tier 2 | Modifies %WinDir%\WinSxS\; requires rollback pre-check |
| `chkdsk C:` (read-only) | Tier 1 | Scan only; no modifications |
| `chkdsk C: /F` or `/R` on system volume | Tier 2 | Schedules pre-boot file system repair; reboot required |
| Service restart (Start-Service) | Tier 2 | Modifies service state; requires config capture as rollback artifact |
| DLL redistributable install (Microsoft installer) | Tier 1 | Microsoft-signed package; reversible by uninstalling via Settings → Apps |
| .NET Framework Repair Tool | Tier 1 | Official Microsoft repair pathway; reversible |

Never present a Tier 2 gate without the rollback pre-check (check-rollback.ps1) running first and passing.

### Two-gate sequencing

When one fix may not be sufficient alone, present two sequential gates — not one bundled gate. This is UX-06 / D-SD4.

The canonical two-gate sequence is SFC → DISM:
- **Gate 1:** Present SFC /scannow (Tier 1). After SFC completes, parse the verbatim output string.
- **Gate 2:** Present DISM /RestoreHealth (Tier 2) ONLY if SFC reports the exact string "Windows Resource Protection found corrupt files but was unable to fix some of them." If SFC succeeds or finds nothing, Gate 2 is never presented.

The user approves each gate separately. The SFC result is the condition that determines whether Gate 2 is relevant. Never bundle the two into one approval.

---

## Windows Update Failures

**What this covers:** Windows Update service failing, stuck, or not running. Applies when collected data shows wuauserv or bits stopped, update-related errors in the System event log (Event 7031/7034 referencing wuauserv, 8024xxxx error codes in event text), or user description mentions Windows Update failing, hanging, or returning errors.

**Trigger conditions:**
- $stoppedServices contains `wuauserv` or `bits` with StartType = Automatic in Stopped state
- $systemEvents contains Event 7031 or 7034 with Source = "Service Control Manager" referencing wuauserv
- $systemEvents contains text matching "Windows Update", "wuauserv", or error codes beginning with "8024"
- User description mentions Windows Update failing, hanging, stuck at a percentage, or returning an error code

**Diagnosis logic (apply to collected data):**
1. Check `$stoppedServices` for `wuauserv` or `bits` in Stopped state with StartType = Automatic
2. Check `$systemEvents` for Event IDs 7031 or 7034 (unexpected service termination) or 7036 (status change — informational only, not a fault signal) with text referencing wuauserv or bits
3. Check `$systemEvents` for text containing "8024" (Windows Update-specific error code prefix)
4. If wuauserv or bits is stopped AND an event confirms unexpected termination: Windows Update cache corruption is the most likely root cause
5. If wuauserv or bits is stopped with no supporting event: cache corruption is still the most likely cause; confidence stays MEDIUM

**Default confidence tier:** MEDIUM (named pattern match; event log confirmation elevates to HIGH)
**Runtime elevation rule:** If `$systemEvents` contains Event ID 7031 or 7034 with Source = "Service Control Manager" referencing wuauserv AND `$ver.isWin10 = true` OR `$ver.isWin11 = true` (client OS confirmed): elevate to HIGH. State reason per D-13.

**Fix classification:** Tier 2 — modifies system state (service stop + directory deletion + service restart). Rollback pre-check via check-rollback.ps1 required before gate.

**Rollback plan text (for approval gate):**
```
Rollback plan:
- System Restore point: [mostRecentDate] ([pointAge_days] days ago). To use: Settings → Update & Security → Recovery → Open System Restore → choose this point.
- Service config backups will be saved to %TEMP%\tier1-svcconfig-[timestamp]-wuauserv.txt and -bits.txt before the fix runs. To restore a service: sc.exe config <service> start= <value> using the saved StartType.
```

**Change diff text (for approval gate, D-06 format):**
```
What changes: The Windows Update service (wuauserv) and Background Intelligent Transfer service (bits) will be temporarily stopped, then restarted. The Software Distribution folder (C:\Windows\SoftwareDistribution\) will be cleared — Windows rebuilds this folder automatically on the next Update check.

Exact paths/keys/services: wuauserv, bits, C:\Windows\SoftwareDistribution\

Time estimate: 2–3 minutes

Restart required: No — services restart automatically as part of the fix.
```

**Fix commands (canonical — escape hatch must match exactly):**
```
# Step A: Capture service configs as rollback artifacts (run BEFORE any fix commands)
WUAUSERV_BACKUP=$(powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command '$f = "$env:TEMP\tier1-svcconfig-$(Get-Date -f yyyyMMdd-HHmmss)-wuauserv.txt"; sc.exe qc wuauserv | Out-File $f; Write-Output $f')
BITS_BACKUP=$(powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command '$f = "$env:TEMP\tier1-svcconfig-$(Get-Date -f yyyyMMdd-HHmmss)-bits.txt"; sc.exe qc bits | Out-File $f; Write-Output $f')

# Step B: Fix commands
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Stop-Service -Name wuauserv -Force"
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Stop-Service -Name bits -Force"
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Remove-Item 'C:\Windows\SoftwareDistribution\*' -Recurse -Force"
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Start-Service -Name wuauserv"
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Start-Service -Name bits"
```

**Post-verification check:**
```
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Get-Service wuauserv, bits | Select-Object Name, Status | ConvertTo-Json"
```
Success: both services show Status = Running.

**Post-fix explanation text (for UX-04):**
```
What was wrong: Windows Update had a corrupt or stuck download cache in the SoftwareDistribution folder. When this folder gets into a bad state, the Update service can't make progress and may stop or error out.

Why it happened: This usually happens after an interrupted download, a failed update installation, or a sudden power loss while an update was in progress. The corruption doesn't spread — it's contained in this folder.

What changed: The SoftwareDistribution folder was cleared and both the wuauserv and bits services were restarted. Windows immediately rebuilds the folder from scratch with a clean state.

Why the fix worked: Clearing the cache removes whatever corrupt or stuck data was blocking the Update service. Windows re-downloads only what it needs — no data was permanently lost.

If something seems off later: Your service config backups are at %TEMP%\tier1-svcconfig-[timestamp]-wuauserv.txt and -bits.txt. A System Restore point from [mostRecentDate] also exists if you need to roll back further.
```

---

## DLL and Runtime Failures

**What this covers:** App crashes due to missing or corrupt Microsoft Visual C++ runtime DLLs and .NET Framework files. Common faulting modules include: VCRUNTIME140.dll, VCRUNTIME140_1.dll, MSVCP140.dll, MSVCP100.dll, MSVCR100.dll, MSVCR110.dll, MSVCR120.dll, api-ms-win-*.dll, mfc140.dll, mfc140u.dll. Also covers .NET Framework repair when System.* assemblies fault.

**Trigger conditions:**
- $appEvents contains Event 1000 with "Faulting Module Name" field matching one of the listed DLLs
- User description names a missing DLL ("VCRUNTIME140.dll is missing" / "the program can't start because MSVCP140.dll was not found")
- User describes "won't open" / "crashes immediately" for an application, including .NET applications

**Diagnosis logic (apply to collected data):**
1. Check `$appEvents` for Event 1000 entries (Source: Application Error)
2. From each Event 1000, extract the "Faulting Module Name" field
3. Match the faulting module name against the DLL-to-package table:
   - VCRUNTIME140.dll, VCRUNTIME140_1.dll, MSVCP140.dll, mfc140.dll, mfc140u.dll → Visual C++ 2015–2022 Redistributable (install both x64 and x86)
   - MSVCP100.dll, MSVCR100.dll → Visual C++ 2010 Redistributable
   - MSVCR110.dll → Visual C++ 2012 Redistributable
   - MSVCR120.dll → Visual C++ 2013 Redistributable
   - api-ms-win-*.dll → Universal CRT (run `sfc /scannow` or Windows Update — route to SFC/DISM section)
4. If Exception Code in Event 1000 is `0xc000007b`: architecture mismatch — a 32-bit application loaded a 64-bit DLL or vice versa. Fix: install BOTH x86 AND x64 versions of the relevant redistributable.
5. If the faulting module is a .NET assembly (names like System.*, mscorlib.dll, clr.dll): route to .NET Framework Repair Tool instead of a redistributable.
6. If no Event 1000 is present but user description names a DLL: treat as MEDIUM confidence match and proceed with the relevant redistributable.

**Default confidence tier:** MEDIUM (named DLL pattern; event log confirmation elevates to HIGH)
**Runtime elevation rule:** If Event 1000 in $appEvents names one of the DLLs in the table AND $ver.osArchitecture is "64-bit" or "ARM 64-bit" (so the matching x64 redistributable applies): elevate to HIGH per safety-protocols.md condition 3 (Application log entry confirms application-layer failure pattern). State elevation reason per D-13.

**Fix classification:** Tier 1 — runtime redistributable is a Microsoft installer; reversible by uninstalling via Settings → Apps → Installed apps. No rollback artifact required. (.NET Framework Repair Tool is also Tier 1 — it is the official Microsoft repair pathway and is reversible.)

**Rollback plan text (for approval gate):**
```
Rollback plan:
These are Microsoft installers. To undo: open Settings → Apps → Installed apps, find the Visual C++ Redistributable package (or .NET Framework entry), and uninstall it. No registry or system file changes outside the installer's own scope.
```

**Change diff text (for approval gate, D-06 format):**
```
What changes: The Microsoft Visual C++ Redistributable package will be downloaded and installed. This installs the runtime DLLs into C:\Windows\System32\ (x64) and C:\Windows\SysWOW64\ (x86).

Exact paths/keys/services: C:\Windows\System32\ (runtime DLLs), standard installer registry entries under HKLM\SOFTWARE\Microsoft\VisualStudio

Time estimate: 2–3 minutes

Restart required: No, unless the installer prompts.
```

**Fix commands (canonical — escape hatch must match exactly):**
```
# Visual C++ 2015–2022 Redistributable — download URLs (user downloads and runs the installer):
# x64: https://aka.ms/vs/17/release/vc_redist.x64.exe
# x86: https://aka.ms/vs/17/release/vc_redist.x86.exe

# Silent install form (if running via Bash/PowerShell after download):
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Start-Process -FilePath 'vc_redist.x64.exe' -ArgumentList '/install /quiet /norestart' -Wait"
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Start-Process -FilePath 'vc_redist.x86.exe' -ArgumentList '/install /quiet /norestart' -Wait"

# For MSVCR100.dll (VC++ 2010 Redistributable):
# Download from: https://www.microsoft.com/en-us/download/details.aspx?id=26999

# For MSVCR110.dll (VC++ 2012 Redistributable):
# Download from: https://www.microsoft.com/en-us/download/details.aspx?id=30679

# For MSVCR120.dll (VC++ 2013 Redistributable):
# Download from: https://www.microsoft.com/en-us/download/details.aspx?id=40784

# For api-ms-win-*.dll: route to sfc /scannow (see SFC/DISM/chkdsk Repair section)

# For .NET Framework failures (System.* assembly faults):
# .NET Framework Repair Tool: https://aka.ms/dotnetrepairtool
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Start-Process -FilePath 'NetFxRepairTool.exe' -ArgumentList '/q' -Wait"
```

**Post-verification check:**
```
# Re-run the application that was crashing.
# OR check for new Event 1000 entries after install:
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Get-WinEvent -LogName Application -MaxEvents 50 | Where-Object {$_.Id -eq 1000} | Select-Object -First 1 TimeCreated, Message | ConvertTo-Json"
```
Success: no new Event 1000 with the same Faulting Module Name after the redistributable install.

**Post-fix explanation text (for UX-04):**
```
What was wrong: The application crashed because it required a Microsoft runtime library (a DLL file) that was either missing from your system or was corrupt. The specific file is named in the Windows Event Log as the faulting module.

Why it happened: Many applications are built using Microsoft's Visual C++ runtime libraries instead of including them directly. These libraries ship separately as "redistributable" packages. If the package was never installed, was removed, or was damaged, any application that depends on it will fail to start.

What changed: The Microsoft Visual C++ Redistributable package was installed. This added the required DLL files to Windows' system folders, making them available to any application that needs them.

Why the fix worked: The application now finds the DLL it was looking for. Runtime redistributable installs don't modify your files — they add Microsoft's own library files to a shared system location.

If something seems off later: The package can be removed via Settings → Apps → Installed apps if needed. No system restore point is required because this is a standard Microsoft installer with a clean uninstall path.
```

---

## SFC/DISM/chkdsk Repair

**What this covers:** System file integrity repair (SFC), Windows component store repair (DISM), and file system error repair (chkdsk). Use when collected data or user description points to corrupted Windows files, "won't start" symptoms not traced to a single application, or hardware-adjacent file corruption signals in $hardwareFaultEvents.

**Trigger conditions:**
- User description mentions "corrupted files," "Windows won't start properly," "files won't open," SFC, DISM, or chkdsk
- $hardwareFaultEvents contains Kernel-Power Event 41, EventLog Event 6008, or WHEA-Logger Events 1/17/18 (hardware-adjacent file corruption signals)
- A previous fix from another section's post-verification failed and points back to system file integrity as the next diagnostic step

**Diagnosis logic (apply to collected data):**
1. If $hardwareFaultEvents contains Kernel-Power Event 41 (unexpected shutdown/crash), EventLog Event 6008 (dirty shutdown), or WHEA-Logger Events 1/17/18 (hardware error): hardware-adjacent file corruption is plausible — route to SFC first to rule out file corruption before considering hardware replacement
2. If $systemEvents contains NTFS errors or disk-related Event IDs, or user reports disk errors: also consider chkdsk read-only scan (Tier 1) as a first diagnostic pass
3. Run SFC first — it is Tier 1, requires no rollback pre-check, and resolves the majority of system file integrity issues
4. After SFC completes, parse the verbatim output string (one of four exact strings — see Fix commands):
   - "did not find any integrity violations" → no corruption; if symptoms persist, the problem is elsewhere — re-route
   - "found corrupt files and successfully repaired them" → success; proceed to post-verification
   - "found corrupt files but was unable to fix some of them" → escalate to DISM /RestoreHealth as a separate Gate 2
   - "could not perform the requested operation" → suggest safe mode rerun; check %WinDir%\WinSxS\Temp for PendingDeletes or PendingRenames entries
5. chkdsk applies when file system errors are suspected — disk read failures, NTFS event log entries. Run `chkdsk C:` read-only first (Tier 1); only escalate to `chkdsk /F` (Tier 2, schedules pre-boot run) if errors are reported

**Default confidence tier:** MEDIUM (SFC is broadly safe and applicable; DISM/chkdsk targeted at confirmed signals)
**Runtime elevation rule:** If $hardwareFaultEvents contains Kernel-Power Event 41 with a BugcheckCode field present AND $ver.isWin10 = true OR $ver.isWin11 = true: elevate the SFC step to HIGH (confirmed crash/corruption pattern on a supported edition). State elevation reason per D-13.

**Fix classification:** TWO SEPARATE GATES (D-SD4) —
- **SFC /scannow → Tier 1.** No rollback pre-check required (check-rollback.ps1 NOT invoked for this gate). Show duration warning ("10–20 minutes typical") and elevation requirement before presenting the gate.
- **DISM /RestoreHealth → Tier 2** (only if SFC reports the verbatim string "found corrupt files but was unable to fix some of them"). Rollback pre-check via check-rollback.ps1 IS required before this gate. SKILL.md performs a connectivity probe before presenting this gate (see Branch logic below). SFC and DISM are NEVER bundled — two gates in sequence per UX-06 / D-SD4.
- **chkdsk read-only → Tier 1**, no rollback pre-check required.
- **chkdsk /F or /R on system volume → Tier 2** (schedules a pre-boot run; reboot disclosure required in change diff).

**Rollback plan text (for approval gate):**
```
SFC rollback plan:
SFC repairs files from the Windows side-by-side store (a built-in known-good cache). The repair is not destructive — files that get repaired are returned to their last-known-good Windows-shipped state. No external rollback artifact is needed.

DISM rollback plan:
DISM /RestoreHealth replaces corrupt component store files with versions downloaded from Windows Update. System Restore point [mostRecentDate] is your safety net for this fix. To use: Settings → Update & Security → Recovery → Open System Restore → choose this point.

chkdsk /F rollback plan:
chkdsk modifies file system structures. System Restore does NOT roll back chkdsk repairs. To cancel the scheduled run before the next reboot: run `chkntfs /X C:` from an elevated prompt before restarting.
```

**Change diff text (for approval gate, D-06 format):**
```
SFC change diff:
What changes: SFC scans every protected Windows system file and repairs any it finds corrupt or missing, sourcing replacements from the Windows side-by-side store.
Exact paths/keys/services: Protected system files under %WinDir%\System32\ and %WinDir%\WinSxS\
Time estimate: 10–20 minutes
Restart required: No

DISM change diff:
What changes: DISM /RestoreHealth scans the Windows component store and downloads replacement components from Windows Update. Modifies %WinDir%\WinSxS\.
Exact paths/keys/services: %WinDir%\WinSxS\ (component store)
Time estimate: 5–30 minutes (varies by connection speed)
Restart required: No, but recommended after completion to settle in changes

chkdsk /F change diff:
What changes: chkdsk schedules a pre-boot scan of the C: drive. The scan runs before Windows starts and repairs file system errors.
Exact paths/keys/services: NTFS file system metadata on C:
Time estimate: Adds 10–30 minutes to next startup
Restart required: YES
```

**Fix commands (canonical — escape hatch must match exactly):**
```
# SFC (Tier 1) — must be run from an elevated PowerShell or Command Prompt session
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "sfc /scannow"

# After SFC completes, parse stdout for one of four verbatim strings:
#   "Windows Resource Protection did not find any integrity violations." → no corruption; no further SFC/DISM action
#   "Windows Resource Protection found corrupt files and successfully repaired them." → success; proceed to post-verification
#   "Windows Resource Protection found corrupt files but was unable to fix some of them." → escalate to DISM gate (Gate 2)
#   "Windows Resource Protection could not perform the requested operation." → suggest safe mode rerun

# DISM /RestoreHealth (Tier 2) — present ONLY after SFC reports "unable to fix some of them"
# SKILL.md performs the connectivity probe before this gate; this section documents the branching

# Online repair (connectivity confirmed by SKILL.md before this gate):
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "DISM /Online /Cleanup-Image /RestoreHealth"

# Offline repair (no internet) — requires Windows installation media (USB or mounted ISO)
# The /Source argument MUST point to install.wim from installation media.
# NOTE: /Source:winsxs is NOT valid syntax — WinSxS is the repair target, not a source.
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "DISM /Online /Cleanup-Image /RestoreHealth /Source:WIM:<drive>:\sources\install.wim:1 /LimitAccess"
# /LimitAccess prevents DISM from falling back to Windows Update when a local source is provided.

# chkdsk read-only scan (Tier 1)
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "chkdsk C:"

# chkdsk /F on system volume (Tier 2 — schedules pre-boot run, reboot required)
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "echo Y | chkdsk C: /F"
```

**Branch logic for offline DISM:**
Before presenting the DISM gate, SKILL.md performs a connectivity probe. If the probe returns false (offline), SKILL.md presents the user with two options:

Option A: "Insert Windows installation media (USB or ISO) and tell me the drive letter — I'll use install.wim from that as the local source." SKILL.md then constructs the command: `DISM /Online /Cleanup-Image /RestoreHealth /Source:WIM:<drive>:\sources\install.wim:1 /LimitAccess` using the user-provided drive letter.

Option B: "Connect to the internet and I'll re-check — DISM /RestoreHealth needs to download replacement components from Windows Update."

The connectivity probe execution lives in SKILL.md (per Architectural Responsibility Map). This section documents the branching logic; SKILL.md is responsible for running the probe and constructing the final command.

**Post-verification check:**
```
# SFC: parse stdout for one of the four verbatim strings (positive outcomes = "did not find" or "successfully repaired them")
# CBS.log is at %windir%\Logs\CBS\CBS.log — contains details on files SFC could not repair

# DISM post-verification:
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "DISM /Online /Cleanup-Image /CheckHealth"
# Success: output contains "No component store corruption detected."

# chkdsk /F post-verification (after reboot):
# After reboot, the scan log appears in Event Viewer → Windows Logs → Application
# Source = "Wininit"; success = "completed successfully" in the event text
# DISM log is at %windir%\Logs\DISM\dism.log
```

**Post-fix explanation text (for UX-04):**
```
What was wrong: Windows found corrupt or missing system files. For SFC repairs: the corruption was in the protected system file area that Windows maintains with known-good copies. For DISM repairs: the corruption was deeper — in the component store that SFC itself relies on.

Why it happened: System file corruption can result from interrupted updates, sudden shutdowns, disk errors, or hardware instability. It doesn't necessarily mean your hardware is failing — even a single interrupted update can leave files in an inconsistent state.

What changed: SFC repaired the corrupt files by replacing them with known-good copies from the Windows side-by-side store (a local cache). If DISM was needed, it replaced corrupt component store files by downloading verified replacements from Windows Update.

Why the fix worked: The replacement files came from Microsoft-verified sources — either the local side-by-side store (SFC) or Windows Update (DISM). Once the corrupt files are replaced, the affected Windows components operate normally again.

If something seems off later: For DISM repairs, a System Restore point from [mostRecentDate] is your safety net. For chkdsk: the scan log is in Event Viewer → Application log, Source = Wininit.
```

---

## Common Service Failures

**What this covers:** Auto-start Windows services that are in Stopped state when they should be running, or services that terminate unexpectedly after starting. Covers the generic diagnosis-and-recovery pattern usable for any auto-start service not specifically routed to another section. (wuauserv and bits route to Windows Update Failures; this section covers everything else.)

**Trigger conditions:**
- $stoppedServices contains one or more services with StartType = Automatic in Stopped state (other than wuauserv or bits, which route to Windows Update Failures)
- $systemEvents contains Event 7031 (service terminated unexpectedly with restart action details) or Event 7034 (service terminated unexpectedly, simpler form) referencing any service name
- Note: Event 7036 is NOT a fault signal — it fires on every normal service start and stop, not just failures. Do not route on Event 7036 alone.

**Diagnosis logic (apply to collected data):**
1. From $stoppedServices, identify the affected service Name and DisplayName (StartType = Automatic, Status = Stopped)
2. Check $systemEvents for Event IDs 7000, 7001, 7009, 7011, 7031, or 7034 entries naming the same service:
   - Event 7001 (dependency failed to start): the service's RequiredServices failed first — run `Get-Service -Name <name> -RequiredServices` and route the dependency as the primary fix target, not the downstream service
   - Event 7009 or 7011 (timeout): service may need a startup type or timeout configuration adjustment, not just a restart; note this in the diagnosis
   - Event 7031 or 7034 (unexpected termination): clean service restart is the appropriate first step
   - Event 7000 (failed to start): may be a permissions issue or a corrupted service binary; a restart attempt is appropriate but may not resolve root cause
3. If no matching system event entry: attempt a clean service restart (Tier 2 with config backup); if the service stops again immediately after restart, the issue is a dependency or configuration problem, not a transient failure
4. If the service repeatedly stops after restart: recommend deeper investigation (manual Event Viewer review) rather than repeat restarts — this is beyond transient failure territory

**Default confidence tier:** MEDIUM (generic pattern; specific service identity and confirming event evidence elevate)
**Runtime elevation rule:** If $stoppedServices names a specific service AND $systemEvents contains Event 7031 or 7034 referencing that exact service name AND $ver.isWin10 = true OR $ver.isWin11 = true: elevate to HIGH. State elevation reason per D-13.

**Fix classification:** Tier 2 — modifies service state (starts a stopped service); depends on captured config as rollback artifact. Rollback pre-check via check-rollback.ps1 required.

**Rollback plan text (for approval gate):**
```
Rollback plan:
Service config will be saved to %TEMP%\tier1-svcconfig-[timestamp]-[ServiceName].txt before the fix runs. This captures the output of `sc.exe qc <ServiceName>` — including Start_Type, Error_Control, Service_Type, and dependencies.
To restore: sc.exe config <ServiceName> start= <originalValue> using the saved Start_Type value.
System Restore point from [mostRecentDate] is the broader safety net if service config changes need to be reversed.
```

**Change diff text (for approval gate, D-06 format):**
```
What changes: The [ServiceName] service (DisplayName: [DisplayName]) will be started. If a dependency service is identified as the root cause, that dependency will be started first.

Exact paths/keys/services: [ServiceName] and any dependency services identified from $systemEvents Event 7001 analysis

Time estimate: Under 1 minute

Restart required: No
```

**Fix commands (canonical — escape hatch must match exactly):**
```
# Step A: Capture service config as rollback artifact (run BEFORE any fix commands)
SVC_BACKUP=$(powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command '$f = "$env:TEMP\tier1-svcconfig-$(Get-Date -f yyyyMMdd-HHmmss)-<ServiceName>.txt"; sc.exe qc <ServiceName> | Out-File $f; Write-Output $f')

# Step B (conditional): If Event 7001 identified a failed dependency, start the dependency first
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Start-Service -Name <DependencyName>"

# Step C: Start the target service
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Start-Service -Name <ServiceName>"
```
Substitute `<ServiceName>` and `<DependencyName>` with the actual service names identified during diagnosis from $stoppedServices and $systemEvents.

**Post-verification check:**
```
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Get-Service -Name <ServiceName> | Select-Object Name, Status | ConvertTo-Json"
```
Success: Status = Running.

If Status = Stopped after the restart attempt: report the config backup path and recommend the user check Event Viewer for the most recent Event 7031 or 7034 referencing this service — this is a deeper issue than a transient stop, and further investigation is needed.

**Post-fix explanation text (for UX-04):**
```
What was wrong: The [DisplayName] service stopped unexpectedly. Depending on the event-log evidence, the cause was one of: a dependency service failing first (Event 7001), a timeout during startup (Event 7009/7011), or a direct unexpected termination (Event 7031/7034).

Why it happened: Service failures can result from dependency chains (one service needed by another stopped first), resource contention during boot, or transient errors that cause the service process to exit. A clean restart re-initializes the service state from disk and often resolves transient failures.

What changed: The [ServiceName] service was started (with its prior config preserved as a rollback artifact in %TEMP%\tier1-svcconfig-[timestamp]-[ServiceName].txt). If a dependency was identified, it was started first.

Why the fix worked: A clean service restart re-initializes the service state. If the underlying cause was a transient one (a boot-time race condition, a one-time error), the restart is sufficient. If the service stops again, the issue is not transient and deeper investigation is warranted.

If something seems off later: The service config backup at %TEMP%\tier1-svcconfig-[timestamp]-[ServiceName].txt contains the original service configuration. The System Restore point from [mostRecentDate] is the broader safety net.
```

---

*This file is a Phase 3 output. It is consumed by SKILL.md and governs routing for the General Windows problem domain.*
*Do not add UX copy (approval gate text, escape hatch instructions) to this file — those belong in SKILL.md.*
