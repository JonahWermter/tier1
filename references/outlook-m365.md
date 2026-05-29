# Outlook/M365 Domain Reference

**Version:** 1.0
**Updated:** 2026-05-20

> **Loading Note:** This file is NOT automatically in context. SKILL.md must explicitly load it via
> the Read tool at session start. There is no `references:` frontmatter field in Claude Code SKILL.md.
> See SKILL.md Session Start section for the exact Read tool call.

---

## Diagnostic Methodology

Mental model for Outlook/M365 problems. Use worked examples when evidence matches; use this section when it doesn't.

### When evidence matches a worked example

Match collected data to a section using SKILL.md Step 3b routing. When a match is found:
1. Apply the section's diagnosis logic against collected variables ($outlookProfileReg, $ostPstFiles, $addinList, $outlookEvents).
2. Use the section's **default confidence tier** as the floor.
3. Apply the section's **runtime elevation rule** — elevate to HIGH when conditions are met, state reason per D-13.
4. Present fix classification, rollback plan, and change diff exactly as documented.

Match must come from data, not user description alone. Description is a secondary routing signal.

### When no worked example matches (D-RT3)

When collected data doesn't match any section:

> "I don't see a clear pattern match for your Outlook problem, but here's how I'd approach it based on the evidence..."

Steps for unmatched problems:
1. State which signals are present ($outlookEvents error IDs, profile registry state, add-in LoadBehavior values) and which are absent.
2. Assign MEDIUM confidence if one or more signals point at a plausible cause; LOW if signals are ambiguous.
3. Propose the most conservative fix — prefer read-only diagnostics before any profile modification.
4. If no safe fix path exists, tell the user what to tell a technician.

### Evidence-collection priorities

- **$outlookProfileReg — HKCU:\Software\Microsoft\Office\16.0\Outlook\Profiles** — primary routing signal for profile corruption. Profile key structure shows whether a default profile is set and how many profiles exist.
- **$outlookEvents — Application log, ProviderName matching *Outlook*** — event errors on startup, crash, or sync failure confirm which problem class applies.
- **$addinList — LoadBehavior field from all three add-in paths** — value 8 (Outlook-disabled) is the primary signal for add-in failures; value 2 (not loaded) is secondary.
- **$ostPstFiles — FullName and Size_MB from LOCALAPPDATA and APPDATA Outlook dirs** — OST size and existence confirm whether OST rebuild is applicable.

### Tier discipline

| Operation | Tier | Rationale |
|-----------|------|-----------|
| `reg export` Outlook profiles (read/export) | Tier 1 | Export only — IS the rollback artifact; no profile modification |
| OST/PST `Copy-Item` to temp (copy only) | Tier 1 | Copy only — IS the data safety net; source untouched |
| Outlook profile registry modification | Tier 2 | Registry write — D-O1 backup must exist and be verified first |
| OST rename/deletion | Tier 2 | Forces full Exchange re-download — D-O1 backup must exist first |
| Add-in registry `Set-ItemProperty` (re-enable) | Tier 2 | Registry write — rollback pre-check via check-rollback.ps1 required |
| Credential cache `cmdkey /delete` | Tier 1 | Credential removal — user re-authenticates on next Outlook launch |

Never present a Tier 2 gate without check-rollback.ps1 running first and passing.

### D-O1 Pre-Backup Gate (Profile Corruption and OST Rebuild)

Before any profile modification or OST operation, run and verify this full backup sequence. This is the D-O1 pre-backup gate — both Profile Corruption and OST Rebuild sections reference it by name.

```powershell
# Step 1: Export Outlook profile registry as rollback artifact
$ts = Get-Date -f yyyyMMdd-HHmmss
reg export "HKCU\Software\Microsoft\Office\16.0\Outlook\Profiles" "$env:TEMP\tier1-outlook-profiles-$ts.reg" /y

# Step 2: Copy all OST/PST files from both known locations (may be slow for large mailboxes)
$ostPaths = @("$env:LOCALAPPDATA\Microsoft\Outlook", "$env:APPDATA\Microsoft\Outlook")
foreach ($dir in $ostPaths) {
    if (Test-Path $dir) {
        Get-ChildItem $dir -Include "*.ost","*.pst" -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item $_.FullName "$env:TEMP\tier1-outlook-$ts-$(Split-Path $_.FullName -Leaf)" -Force
        }
    }
}

# Step 3: Verify each artifact exists — HARD STOP if any missing
$regArtifact = "$env:TEMP\tier1-outlook-profiles-$ts.reg"
if (-not (Test-Path $regArtifact)) {
    Write-Error "HARD STOP: Outlook profile backup not created. Do not proceed with profile modification."
    exit 1
}
```

If the registry export fails or the .reg file is missing: **HARD STOP** — do not present the fix gate. Tell the user backup failed and ask them to check that Outlook 16.0 is installed and the Profiles key exists.

---

## Profile Corruption

**What this covers:** Outlook fails to open due to a corrupt or misconfigured profile. Applies when Outlook won't start, shows a profile selection dialog on every launch, or shows "Cannot start Microsoft Outlook" errors.

**Trigger conditions:**
- User description: "Outlook won't open", "Cannot start Microsoft Outlook", profile dialog on every launch, Outlook crashes immediately on start
- $outlookEvents contains errors on startup (ProviderName matching Outlook, recent timestamps)
- $outlookProfileReg is empty, missing, or shows no default profile set

**Diagnosis logic (apply to collected data):**
1. Check $outlookProfileReg — does `HKCU:\Software\Microsoft\Office\16.0\Outlook\Profiles` exist with at least one profile subkey?
2. Check $outlookEvents for Outlook Application errors at or after last attempted Outlook launch.
3. If profile key is missing entirely: profile was deleted or never created — new profile creation is the fix.
4. If profile key exists but is malformed (no default set, 0-byte subkeys): profile rebuild is the fix.
5. If events show a specific add-in crash on startup: route to Add-in Failures section first.

**Default confidence tier:** MEDIUM (named pattern; event log confirmation of startup crash elevates to HIGH)
**Runtime elevation rule:** If $outlookEvents contains an Outlook error at the timestamp of last reported Outlook failure AND $ver.isWin10 = true OR $ver.isWin11 = true: elevate to HIGH. State reason per D-13.

**Fix classification:** Tier 2 — profile registry modification (write). D-O1 pre-backup gate (see Methodology) MUST run and pass before this gate is presented.

**Rollback plan text (for approval gate):**
```
Rollback plan:
- Outlook profile registry backup: %TEMP%\tier1-outlook-profiles-[ts].reg — created by D-O1 pre-backup gate.
  To restore: double-click the .reg file and confirm the import. This restores the exact profile state.
- OST/PST backup copies: %TEMP%\tier1-outlook-[ts]-[filename].ost/.pst — copies of all data files.
  To use: rename or copy back to the original location in %LOCALAPPDATA%\Microsoft\Outlook\ or
  %APPDATA%\Microsoft\Outlook\.
- System Restore point from [mostRecentDate] is the broader safety net.
```

**Change diff text (for approval gate, D-06 format):**
```
What changes: A new Outlook profile will be created. The existing corrupt profile registry keys under
HKCU\Software\Microsoft\Office\16.0\Outlook\Profiles will be removed and replaced with a fresh profile.

Exact paths/keys/services: HKCU\Software\Microsoft\Office\16.0\Outlook\Profiles

Time estimate: 2–5 minutes (profile creation + re-adding the email account)

Restart required: No — Outlook restart is sufficient.
```

**Fix commands (canonical — escape hatch must match exactly):**
```powershell
# Step 1: Run the D-O1 pre-backup gate (see Methodology — mandatory before this step)

# Step 2: Open Outlook profile manager — user creates a new profile via the UI
# (No PowerShell for profile creation — Outlook profile API is COM-based)
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Start-Process 'control' -ArgumentList 'mlcfg32.cpl'"

# Instructs user:
# 1. Click "Add" in Mail Setup dialog → Enter a new profile name → Configure email account
# 2. Under "When starting Microsoft Outlook, use this profile" → select "Always use this profile" → select new profile
# 3. Click OK and launch Outlook to verify

# Step 3 (optional cleanup — only if new profile works): Remove old corrupt profile via UI
# (Do not delete via registry manually — use Outlook Mail Setup dialog Remove button)
```

**Post-verification check:**
```powershell
# Verify Outlook launches without error
# Check for new error events after launch:
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Get-WinEvent -LogName Application -MaxEvents 20 -ErrorAction SilentlyContinue | Where-Object {`$_.ProviderName -like '*Outlook*' -and `$_.Level -le 2} | Select-Object TimeCreated, Id, Message | ConvertTo-Json"
```
Success: Outlook opens to inbox without profile dialog. No new Level 1–2 Outlook events after launch.

**Post-fix explanation text (for UX-04):**
```
What was wrong: Outlook's profile — the configuration record that stores your email account
settings, server connections, and data file locations — became corrupt or unreadable.

Why it happened: Profile corruption typically results from an interrupted Outlook update,
a forced shutdown while Outlook was writing to the profile registry, or a previous failed
migration or repair attempt.

What changed: A new Outlook profile was created with a clean registry structure. The old
corrupt profile remains in the Mail Setup dialog until you explicitly remove it.

Why the fix worked: A clean profile gives Outlook a fresh, valid configuration to start from.
Your email data (OST/PST files) is separate from the profile and remains intact.

If something seems off later: The profile registry backup is at
%TEMP%\tier1-outlook-profiles-[ts].reg — double-click to restore. OST/PST backup copies
are at %TEMP%\tier1-outlook-[ts]-[filename] if data recovery is needed.
```

---

## Add-in Failures

**What this covers:** Outlook runs but specific features are missing, Outlook is slow to start, or a notification says an add-in was disabled. Applies when add-in LoadBehavior shows value 8 (Outlook-disabled) or 2 (not loaded).

**Trigger conditions:**
- User description: "Outlook is slow to start", "my [feature] add-in stopped working", "Outlook disabled an add-in", add-in crash notification in Outlook
- $addinList contains one or more add-ins with LoadBehavior = 8 (Outlook disabled due to slow load) or LoadBehavior = 2 (not loaded)
- $outlookEvents contains Outlook startup performance or add-in crash entries

**Diagnosis logic (apply to collected data):**
1. Query all three add-in registry paths (in diagnostic collection — see DIAG-02):
   - `HKLM:\SOFTWARE\Microsoft\Office\16.0\Outlook\Addins\*` — machine-level add-ins
   - `HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\16.0\Outlook\Addins\*` — 32-bit add-ins on 64-bit Windows
   - `HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Addins\*` — user-level add-ins
2. For each add-in, interpret LoadBehavior:
   - **3** = connected and loaded — add-in is active and functioning
   - **2** = not loaded — add-in is installed but disabled (user-level or policy)
   - **8** = connected but not loaded — Outlook automatically disabled it due to slow startup time
3. Add-ins with LoadBehavior = 8 are managed by Outlook's resiliency keys. Re-enabling sets LoadBehavior back to 3, but Outlook will disable again if the add-in remains slow.
4. Check $outlookEvents for add-in crash records — if present, re-enabling without fixing the add-in will only delay recurrence.
5. If LoadBehavior is 3 for all add-ins but user reports missing feature: the add-in may be installed for a different Office version (15.0 path vs 16.0) — out of v1 scope; disclose.

**Default confidence tier:** MEDIUM (named pattern match; LoadBehavior = 8 confirmation elevates)
**Runtime elevation rule:** If $addinList contains any add-in with LoadBehavior = 8 AND the affected add-in name matches user-reported missing feature AND $ver.isWin10 = true OR $ver.isWin11 = true: elevate to HIGH. State reason per D-13.

**Fix classification:** Tier 1 for diagnostic read (LoadBehavior enumeration — read-only). Tier 2 for add-in re-enable (registry write — sets LoadBehavior = 3). Rollback pre-check via check-rollback.ps1 required for Tier 2 gate.

**Rollback plan text (for approval gate):**
```
Rollback plan:
- Registry backup of the add-in key will be saved to %TEMP%\tier1-addin-[addinname]-[ts].reg before modification.
  To restore: double-click the .reg file to reimport the original LoadBehavior value.
- If re-enabling causes Outlook to hang at startup: open Outlook in safe mode (outlook.exe /safe),
  navigate to File → Options → Add-ins → COM Add-ins → Go, and uncheck the add-in.
- System Restore point from [mostRecentDate] is the broader safety net.
```

**Change diff text (for approval gate, D-06 format):**
```
What changes: The LoadBehavior registry value for [add-in name] will be set from 8 (or 2) to 3,
which tells Outlook to load this add-in at startup.

Exact paths/keys/services: HKLM:\SOFTWARE\Microsoft\Office\16.0\Outlook\Addins\[addinname]\LoadBehavior
  (or HKCU path if it's a user-level add-in)

Time estimate: Under 1 minute

Restart required: No — Outlook restart is sufficient to apply the change.
```

**Fix commands (canonical — escape hatch must match exactly):**
```powershell
# Step 1: Backup the add-in registry key before modification
$addinName = "<addinname>"   # substitute actual add-in registry key name
$addinPath = "HKLM:\SOFTWARE\Microsoft\Office\16.0\Outlook\Addins\$addinName"
# (Use HKCU path if LoadBehavior = 8 was found under HKCU)
$ts = Get-Date -f yyyyMMdd-HHmmss
reg export "HKLM\SOFTWARE\Microsoft\Office\16.0\Outlook\Addins\$addinName" "$env:TEMP\tier1-addin-$addinName-$ts.reg" /y

# Step 2: Set LoadBehavior to 3 (connected and loaded)
Set-ItemProperty -Path $addinPath -Name "LoadBehavior" -Value 3 -Type DWord

# Step 3: Restart Outlook
Stop-Process -Name OUTLOOK -Force -ErrorAction SilentlyContinue
```

**Post-verification check:**
```powershell
# Verify LoadBehavior is now 3
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\16.0\Outlook\Addins\<addinname>' | Select-Object PSChildName, LoadBehavior | ConvertTo-Json"
```
Success: LoadBehavior = 3. After Outlook restart, add-in is listed as active in File → Options → Add-ins.

**Post-fix explanation text (for UX-04):**
```
What was wrong: Outlook disabled the [add-in name] add-in automatically. Outlook does this when
an add-in causes startup to take longer than its threshold — it sets LoadBehavior to 8 to protect
startup time.

Why it happened: The add-in may be performing heavy initialization at startup (a version update,
a network check, or a heavy COM registration). Outlook's resiliency mechanism treats any add-in
that slows startup beyond a threshold as a candidate for automatic disabling.

What changed: The add-in's LoadBehavior registry value was reset to 3 (connected and loaded).
Outlook will now attempt to load it on the next startup.

Why the fix worked: Resetting LoadBehavior tells Outlook to try loading the add-in again. If the
add-in now starts faster (e.g., after an update), it will stay enabled. If Outlook disables it
again, the add-in's own performance is the root cause.

If something seems off later: The registry backup is at %TEMP%\tier1-addin-[addinname]-[ts].reg.
If Outlook hangs at startup, start Outlook in safe mode (outlook.exe /safe) and disable the
add-in via File → Options → Add-ins.
```

---

## OST Rebuild

**What this covers:** Mailbox sync issues, calendar inconsistencies, Outlook hanging on "Processing", or other data file integrity problems. Applies when the OST (Offline Storage Table) file is corrupt or out of sync with the Exchange server.

**Trigger conditions:**
- User description: "Outlook stuck on Processing", "calendar events missing", "mailbox not syncing", "sent items not showing", Outlook hangs during send/receive
- $ostPstFiles shows an unusually large OST file (> 10 GB may indicate bloat or corruption)
- $outlookEvents contains sync errors or data file errors mentioning OST

**Diagnosis logic (apply to collected data):**
1. Check $ostPstFiles for OST file size — very large files (> 10 GB) are more prone to sync issues.
2. Check $outlookEvents for sync errors, data file errors, or "Synchronization Log" entries indicating repeated failures.
3. Check if Outlook is connected to Exchange/M365 — if offline, sync issues are expected (not corruption).
4. If OST exists and is large with sync errors: OST rebuild is the primary fix path.
5. If no OST exists (POP/IMAP account without Exchange): this section does not apply — route to Profile Corruption or research subagent.

**Default confidence tier:** MEDIUM (sync errors + large OST size elevates to HIGH)
**Runtime elevation rule:** If $outlookEvents contains repeated sync errors (3+ entries in recent events) AND $ostPstFiles shows OST > 5 GB AND $ver.isWin10 = true OR $ver.isWin11 = true: elevate to HIGH. State reason per D-13.

**Fix classification:** Tier 2 — OST rename forces full Exchange re-download. D-O1 pre-backup gate (see Methodology) MUST run and pass before this gate is presented. The OST is renamed (NOT deleted) to preserve a fallback.

**Rollback plan text (for approval gate):**
```
Rollback plan:
- The existing OST file will be renamed to .ost.bak (NOT deleted). If the rebuild fails or causes
  issues, rename it back: Remove the new .ost file, rename .ost.bak back to .ost.
- OST/PST backup copies created by D-O1 pre-backup: %TEMP%\tier1-outlook-[ts]-[filename].ost/.pst
- Outlook profile registry backup: %TEMP%\tier1-outlook-profiles-[ts].reg
- System Restore point from [mostRecentDate] is the broader safety net.
- Important: OST rebuild re-downloads all mail from Exchange. This may take significant time for
  large mailboxes and uses network bandwidth.
```

**Change diff text (for approval gate, D-06 format):**
```
What changes: Outlook will be closed, the existing OST file will be renamed from .ost to .ost.bak,
and Outlook will be reopened. On launch, Outlook creates a fresh OST and re-downloads all mail from
the Exchange server.

Exact paths/keys/services: %LOCALAPPDATA%\Microsoft\Outlook\[account].ost → renamed to .ost.bak

Time estimate: 2–3 minutes for the rename. Full mailbox re-download may take 30+ minutes depending
on mailbox size and connection speed.

Restart required: No system restart — Outlook restart is part of the fix.
```

**Fix commands (canonical — escape hatch must match exactly):**
```powershell
# Step 1: Run the D-O1 pre-backup gate (see Methodology — mandatory before this step)

# Step 2: Close Outlook
Stop-Process -Name OUTLOOK -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# Step 3: Rename the OST file (NOT delete)
$ostDir = "$env:LOCALAPPDATA\Microsoft\Outlook"
$ts = Get-Date -f yyyyMMdd-HHmmss
Get-ChildItem -Path $ostDir -Include "*.ost" -ErrorAction SilentlyContinue | ForEach-Object {
    $newName = "$($_.FullName).bak-$ts"
    Rename-Item $_.FullName $newName -Force
    Write-Output "Renamed: $($_.FullName) → $newName"
}

# Step 4: Verify rename succeeded
Get-ChildItem -Path $ostDir -Include "*.ost" -ErrorAction SilentlyContinue
# Should return empty — no .ost files remain

# Step 5: Reopen Outlook — it will create a fresh OST and begin re-downloading from Exchange
Start-Process "outlook.exe"
```

**Post-verification check:**
```powershell
# Verify new OST was created (check after Outlook has been open for a few minutes)
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Get-ChildItem '$env:LOCALAPPDATA\Microsoft\Outlook\*.ost' -ErrorAction SilentlyContinue | Select-Object FullName, @{N='Size_MB';E={[math]::Round(`$_.Length/1MB,1)}}, LastWriteTime | ConvertTo-Json"
```
Success: new .ost file exists with recent LastWriteTime. Outlook is syncing mail (check Send/Receive progress bar).

**Post-fix explanation text (for UX-04):**
```
What was wrong: Outlook's offline data file (OST) had become corrupt or severely out of sync with
the Exchange server. The OST stores a local copy of your mailbox for offline access — when it's
damaged, Outlook can't reliably sync, which causes missing items, stuck Processing states, and
calendar inconsistencies.

Why it happened: OST corruption typically results from an interrupted sync (network drop during a
large operation), an Outlook crash during a write operation, or accumulated data inconsistencies
over time in a very large mailbox.

What changed: The old OST file was renamed to .ost.bak (preserved as a backup), and Outlook
created a fresh OST from scratch. All mail is being re-downloaded from the Exchange server.

Why the fix worked: A fresh OST starts with a clean sync state. Exchange is the authoritative
copy of your mailbox — the OST is just a local cache. Re-downloading rebuilds the cache without
the corruption.

If something seems off later: The old OST is at %LOCALAPPDATA%\Microsoft\Outlook\[account].ost.bak-[ts].
To revert: close Outlook, delete the new .ost, rename .ost.bak-[ts] back to .ost. D-O1 backup copies
are also at %TEMP%\tier1-outlook-[ts]-[filename].
```

---

## M365 Authentication Failures

**What this covers:** Repeated password prompts, "Need Password" notifications, account showing as disconnected in Outlook, or modern authentication token failures. Applies when M365/Exchange Online credentials are not being accepted client-side.

**Trigger conditions:**
- User description: "Outlook keeps asking for my password", "Need Password notification", "account disconnected", "can't sign in to Office", repeated credential prompts
- Outlook shows account status as "Disconnected" or "Need Password" in the status bar
- $outlookEvents contains authentication errors or token renewal failures

**Diagnosis logic (apply to collected data):**
1. Check $outlookEvents for authentication-related errors (token renewal, credential manager failures, ADAL/MSAL errors).
2. Check credential cache state: `cmdkey /list` — look for entries matching `MicrosoftOffice16_*` or `Microsoft_OC_*` or `*microsoftonline*`.
3. If stale credentials found in cache: clearing them forces a fresh authentication flow on next Outlook launch.
4. If no cached credentials and still failing: check if modern auth is enabled (registry key `HKCU:\Software\Microsoft\Office\16.0\Common\Identity\EnableADAL` should be 1).
5. If issue persists after credential clear: likely server-side (tenant policy, MFA change, license issue) — honest disclosure required.

> **Honest disclosure:** Client-side credential reset resolves approximately 70% of M365 auth failures. If the issue is server-side (tenant policy change, license revocation, MFA reconfiguration, Conditional Access policy), this fix won't help — escalate to M365 admin. The skill cannot diagnose server-side M365 issues.

**Default confidence tier:** MEDIUM (auth issues may stem from server-side causes not visible to client)
**Runtime elevation rule:** If `cmdkey /list` returns stale M365 credentials AND $outlookEvents contains auth errors in recent timeline AND $ver.isWin10 = true OR $ver.isWin11 = true: elevate to HIGH. State reason per D-13.

**Fix classification:** Tier 1 for credential cache clear (`cmdkey /delete` — removes cached credentials; user re-authenticates on next launch). Tier 2 for profile credential reset (registry modification).

**Rollback plan text (for approval gate):**
```
Rollback plan:
- Credential cache clear is reversible by re-entering your credentials on next Outlook launch.
  No permanent data is lost — you will simply be prompted to sign in again.
- If the sign-in prompt doesn't appear or fails: restart Outlook, then try signing in via
  File → Office Account → Sign In.
- System Restore point from [mostRecentDate] is the broader safety net if registry changes were made.
```

**Change diff text (for approval gate, D-06 format):**
```
What changes: Cached M365/Office credentials in the Windows Credential Manager will be removed.
On next Outlook launch, you will be prompted to sign in with your Microsoft 365 credentials.

Exact paths/keys/services: Windows Credential Manager entries matching MicrosoftOffice16_*, Microsoft_OC_*

Time estimate: Under 1 minute

Restart required: No — Outlook restart is sufficient.
```

**Fix commands (canonical — escape hatch must match exactly):**
```powershell
# Step 1: Close Outlook
Stop-Process -Name OUTLOOK -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Step 2: List current M365-related credentials (diagnostic — shows what will be removed)
cmdkey /list | Select-String -Pattern "MicrosoftOffice|Microsoft_OC|microsoftonline"

# Step 3: Remove cached M365 credentials
$creds = cmdkey /list | Select-String -Pattern "Target:\s+(MicrosoftOffice16_\S+|Microsoft_OC_\S+)" -AllMatches
foreach ($match in $creds.Matches) {
    $target = $match.Groups[1].Value
    cmdkey /delete:$target
    Write-Output "Removed: $target"
}

# Step 4: Clear Office identity cache (optional — for persistent token issues)
$identityPath = "HKCU:\Software\Microsoft\Office\16.0\Common\Identity"
if (Test-Path $identityPath) {
    Remove-ItemProperty -Path $identityPath -Name "SignedOutADUser" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $identityPath -Name "SignedOutWLIDUser" -ErrorAction SilentlyContinue
}

# Step 5: Reopen Outlook — user will be prompted to re-authenticate
Start-Process "outlook.exe"
```

**Post-verification check:**
```powershell
# Verify credentials were removed (should return no matches or fewer entries)
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "cmdkey /list | Select-String 'MicrosoftOffice|Microsoft_OC'"
# Verify Outlook shows account as Connected after user re-authenticates
```
Success: Outlook launches with authentication prompt. After user enters credentials, account shows "Connected" in status bar.

**Post-fix explanation text (for UX-04):**
```
What was wrong: Outlook's cached authentication tokens in the Windows Credential Manager were stale
or corrupt, preventing Outlook from connecting to your M365 mailbox.

Why it happened: Cached credentials can become invalid after a password change, MFA reconfiguration,
a Windows update that affected the credential store, or token expiration that wasn't cleanly renewed.

What changed: The stale M365 credentials were removed from the Windows Credential Manager, and
Outlook's identity cache was cleared. You signed in fresh with current credentials.

Why the fix worked: Removing the stale tokens forced Outlook to perform a clean authentication
handshake with M365. The new tokens are valid and properly cached for future sessions.

If something seems off later: If password prompts return, the cause may be server-side (M365 admin
policy, MFA change, license issue). Contact your M365 administrator. System Restore point from
[mostRecentDate] is available if registry changes need reverting.
```

---

## DIAG-02 Targeted Collection

Post-routing collection commands for Outlook/M365 domain. Invoked by SKILL.md after Step 3b routes to outlook-m365.md. Each command runs via Bash tool. Soft-fail rule: if any command fails or returns empty, set variable = "" and continue.

```powershell
# 1. Profile registry state (export as diagnostic artifact)
$outlookProfileReg = ""
try {
    reg export "HKCU\Software\Microsoft\Office\16.0\Outlook\Profiles" "$env:TEMP\tier1-outlook-profiles-export.reg" /y 2>$null
    $outlookProfileReg = "exported to $env:TEMP\tier1-outlook-profiles-export.reg"
} catch { $outlookProfileReg = "" }
# soft-fail: if export fails, $outlookProfileReg = ""

# 2. OST/PST file paths and sizes
$ostPstFiles = ""
$ostPstFiles = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\Outlook\","$env:APPDATA\Microsoft\Outlook\" -Include "*.ost","*.pst" -Recurse -ErrorAction SilentlyContinue |
    Select-Object FullName, @{N='Size_MB';E={[math]::Round($_.Length/1MB,1)}} |
    ConvertTo-Json
# soft-fail: if no files found or paths missing, $ostPstFiles = ""

# 3. Add-ins list (all three registry paths — soft-fail each)
$addinList = @()
$addinList += Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Office\16.0\Outlook\Addins\*" -ErrorAction SilentlyContinue | Select-Object PSChildName, LoadBehavior
$addinList += Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\16.0\Outlook\Addins\*" -ErrorAction SilentlyContinue | Select-Object PSChildName, LoadBehavior
$addinList += Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Addins\*" -ErrorAction SilentlyContinue | Select-Object PSChildName, LoadBehavior
$addinList = $addinList | ConvertTo-Json
# soft-fail: if all paths fail, $addinList = ""

# 4. Recent Outlook-specific Application event errors (last 50)
$outlookEvents = ""
$outlookEvents = Get-WinEvent -LogName Application -MaxEvents 50 -ErrorAction SilentlyContinue |
    Where-Object {$_.ProviderName -like '*Outlook*' -or $_.ProviderName -like '*OUTLOOK*'} |
    Select-Object TimeCreated, Id, Message |
    ConvertTo-Json
# soft-fail: if no events or log access fails, $outlookEvents = ""
```

---

*Phase 4 output. Consumed by SKILL.md and governs routing, diagnosis, and fix proposals for the Outlook/M365 problem domain.*
*Do not add UX copy (approval gate text, escape hatch instructions, refusal message wording) to this file — those belong in SKILL.md.*
