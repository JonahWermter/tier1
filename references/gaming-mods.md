# Gaming Mods Domain Reference

**Version:** 1.0
**Updated:** 2026-05-20

> **Loading Note:** This file is NOT automatically in context. SKILL.md must explicitly load it via
> the Read tool at session start. There is no `references:` frontmatter field in Claude Code SKILL.md.
> See SKILL.md Session Start section for the exact Read tool call.

---

## Diagnostic Methodology

Mental model behind the 4 worked examples below. Use when evidence doesn't cleanly match a named section; use the worked examples when it does.

### When evidence matches a worked example

Match collected data to a section using routing priority from SKILL.md Step 3b. When match found:
1. Apply section's diagnosis logic against $modManagers, $vortexLog, $unsignedExes, and universal collection variables.
2. Use section's **default confidence tier** as the floor.
3. Apply section's **runtime elevation rule** — if conditions met, elevate to HIGH and state reason per D-13.
4. Present fix classification, rollback plan, and change diff exactly as documented.

Match must come from data, not user description alone — description is secondary routing signal.

### When no worked example matches (D-RT3)

When collected data doesn't cleanly match any of the 4 sections, do NOT refuse or escalate prematurely. Apply methodology with explicit confidence uncertainty:

> "I don't see a clear pattern match for your exact mod problem, but here's how I'd approach it based on the evidence..."

Steps:
1. State which signals are present ($modManagers contents, $vortexLog errors, $unsignedExes hits) and which are absent.
2. Assign MEDIUM confidence if one or more signals point at a plausible cause; LOW if ambiguous.
3. Propose the most conservative fix — prefer read-only diagnostics (log review, Get-AuthenticodeSignature scan) over state-modifying operations.
4. If no safe fix path exists, tell the user what to tell a technician: describe observed signals and symptoms.

Goal is informed forward progress, not paralysis.

### Evidence-collection priorities

For Gaming Mods problems, these signals matter most:

- **$modManagers** — which mod managers are installed (Vortex at $env:APPDATA\Vortex, MO2 at $env:LOCALAPPDATA\ModOrganizer, NMM at $env:LOCALAPPDATA\NexusModManager). Primary routing signal; determines which manager-specific paths apply.
- **$vortexLog tail** — last 100 lines of $env:APPDATA\Vortex\logs\main.log. Contains deployment errors, crash reasons, plugin conflicts. High-signal for Vortex failures.
- **$unsignedExes** — Get-AuthenticodeSignature scan of staging area. Files with Status != Valid. Primary signal for mod safety concerns.
- **User's mod list and recent changes** — secondary routing signal for load order conflicts. "Which mods did you recently add?" narrows hypothesis space faster than any automated scan.

### Tier discipline

Before any fix proposal, apply the correct tier classification:

| Operation | Tier | Rationale |
|-----------|------|-----------|
| `Get-AuthenticodeSignature` (mod check) | Tier 1 | Read-only signature verification; no system state change |
| Vortex log read (`Get-Content`) | Tier 1 | Read-only diagnostic collection |
| Mod load order file write (`plugins.txt`, `loadorder.txt`) | Tier 2 | File modification; `Copy-Item` backup required before write |
| Mod manager reinstall / re-deployment | Tier 2 | Modifies application state; rollback pre-check required |

Never present a Tier 2 gate without the rollback pre-check (check-rollback.ps1) running first and passing.

### Three-stage parallel pattern (D-G4)

Used for Load Order Conflict diagnosis. Unlike sequential diagnosis, this pattern runs two reasoning tracks simultaneously and combines output:

1. **Research synthesis** — apply knowledge of the game + mod list + symptoms: what known conflicts exist for this game/mod combination? What load order rules apply?
2. **Guided walkthrough** — ask user targeted questions in parallel: which mods were recently added? Does disabling specific mods stop the crash? What does the game's crash log say?
3. **Synthesizer step** — after both tracks produce output, merge into one coherent plan: load order adjustment + specific mod culprit hypothesis + verification step.

This is in-turn structured reasoning following the D-C4 schema — NOT an Agent tool invocation. No `allowed-tools` change is needed or permitted. The synthesizer step is also in-turn reasoning.

D-C4 return schema for synthesizer output:
```
{
  confidence: HIGH | MEDIUM | LOW,
  key_findings: ["finding 1", "finding 2", ...],
  recommended_action: "specific next step",
  caveats: ["caveat 1", ...],
  sources_quality: "description of knowledge basis"
}
```

---

## Mod Manager Failure

**What this covers:** Vortex, MO2, NMM, or Steam Workshop crashing, failing to deploy mods, or erroring on launch. Covers Big 3 managers per D-G2/D-G3 with general patterns for others.

**Trigger conditions:**
- $modManagers contains Vortex path AND $vortexLog contains "error", "crash", or "failed to deploy"
- User description mentions mod manager crashing, "Vortex won't open", "MO2 won't deploy", error on launch
- Game launches but mods not active — post-install deployment never ran

**Diagnosis logic (apply to collected data):**
1. Check $modManagers to identify which manager(s) are installed (Vortex: $env:APPDATA\Vortex; MO2: $env:LOCALAPPDATA\ModOrganizer; NMM: $env:LOCALAPPDATA\NexusModManager)
2. Check $vortexLog tail for: "error" lines, "failed to deploy", "EXCEPTION", or "undefined" — extract the specific error message
3. Manager-specific patterns:
   - **Vortex:** Staging folder at $env:APPDATA\Vortex\staging\ — permission errors, staging folder lock, corrupt mod archive
   - **MO2 (instanced mode):** Data at $env:LOCALAPPDATA\ModOrganizer\ — profile corruption, VFS (virtual filesystem) failure, wrong game executable path
   - **MO2 (portable mode):** Data in MO2 install dir (user-defined) — check logs\ subfolder for "failed to run" entries
   - **Steam Workshop:** Subscription mismatch — game shows mod subscribed but files not downloaded; check steamapps\workshop\content\<AppId>\
   - **Other managers:** Check for runtime elevation requirements — some managers require UAC elevation on launch
4. If $vortexLog contains error on deployment: check for staging folder permission errors or locked files
5. If no error in log but manager crashes: likely a runtime elevation issue or corrupt manager install — reinstall path applies

**Default confidence tier:** MEDIUM (manager path presence + log entry confirmation elevates to HIGH)
**Runtime elevation rule:** If $modManagers confirms manager path present AND $vortexLog contains a specific error string AND $ver.isWin10 = true OR $ver.isWin11 = true: elevate to HIGH. State reason per D-13.

**Fix classification:** Tier 1 for diagnostic log review; Tier 2 for manager reinstall (modifies application state). Rollback pre-check via check-rollback.ps1 required before reinstall gate.

**Rollback plan text (for approval gate):**
```
Rollback plan:
- Vortex staging folder: your mod files are in $env:APPDATA\Vortex\staging\ — these are NOT deleted by a manager reinstall. Only the manager application is affected.
- MO2 instanced mode: profiles and mod metadata at $env:LOCALAPPDATA\ModOrganizer\ are preserved across reinstalls — only the MO2 executable is replaced.
- System Restore point: [mostRecentDate] ([pointAge_days] days ago). To use: Settings → Update & Security → Recovery → Open System Restore → choose this point.
- If you need to revert to the previous manager install: uninstall via Settings → Apps → Installed apps, then reinstall the previous version from Nexus Mods or the manager's official site.
```

**Change diff text (for approval gate, D-06 format):**
```
What changes: The mod manager application will be uninstalled and reinstalled. Mod files in the staging area are NOT affected — only the manager executable and its application data are replaced.

Exact paths/keys/services: Vortex: %APPDATA%\Vortex\ (app data, NOT staging files). MO2: %LOCALAPPDATA%\ModOrganizer\ (instanced) or install dir (portable).

Time estimate: 5–10 minutes (download + install)

Restart required: No, unless installer prompts.
```

**Fix commands (canonical — escape hatch must match exactly):**
```powershell
# Step 1: Capture current manager version before uninstall
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.DisplayName -like '*Vortex*' -or $_.DisplayName -like '*Mod Organizer*' } | Select-Object DisplayName, DisplayVersion | ConvertTo-Json"

# Step 2: Reinstall — user downloads latest installer from official source:
# Vortex: https://github.com/Nexus-Mods/Vortex/releases/latest
# MO2: https://github.com/ModOrganizer2/modorganizer/releases/latest
# Run installer after download — follow prompts; do NOT change staging folder location during reinstall

# Step 3 (MO2 only): After reinstall, verify VFS is working:
# Launch MO2 → select game → run a game executable → confirm mods load
```

**Post-verification check:**
```powershell
# Verify manager is present and runs without error
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Test-Path '$env:APPDATA\Vortex'"
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Get-Content '$env:APPDATA\Vortex\logs\main.log' -Tail 20 -ErrorAction SilentlyContinue"
```
Success: manager launches without error dialog; Vortex log tail shows no new error/crash entries; mods deploy to game directory.

**Post-fix explanation text (for UX-04):**
```
What was wrong: The mod manager application had a corrupt installation or a configuration state that prevented deployment. The specific cause was identified in the manager's log file.

Why it happened: Mod manager failures commonly result from: a mid-install power loss or interrupted update, Windows permissions changing on the staging folder, a corrupt mod archive that caused the manager to error out, or a Windows update that changed a dependency the manager relies on.

What changed: The mod manager was reinstalled with a clean application state. Your mod files in the staging folder were not affected — only the manager executable and its internal configuration were replaced.

Why the fix worked: A fresh install removes whatever corrupt state was preventing deployment. Because mod files are stored separately from the manager application, your mods remain intact and the manager can rediscover them on first launch.

If something seems off later: Your mod files are in the staging folder (Vortex: %APPDATA%\Vortex\staging\; MO2: instance folder). The System Restore point from [mostRecentDate] is the broader safety net.
```

---

## Load Order Conflict

**What this covers:** Game crashes caused by specific mod combinations, missing master files, or plugins loading in wrong order. Applies when a game crashes on launch or during load, especially after a mod change, with or without a specific error.

**Trigger conditions:**
- User description: game crashes after adding a mod, crash on specific area load, "missing master" error, CTD (crash to desktop) after mod change
- User reports crash only happens with a specific mod combination active
- Game's crash log (if present) names a specific mod or plugin file

**Diagnosis logic — three-stage parallel pattern (D-G4):**

**Stage 1 — Research synthesis (run first, simultaneously with Stage 2):**
1. Apply knowledge: what load order rules apply for this game (e.g., Skyrim: LOOT conventions; Fallout: ESM before ESP; Minecraft Forge: mod dependency order)?
2. Synthesize known conflict patterns for named mods if the user provides a mod list
3. Identify likely culprits from symptoms: crash on cell boundary → navmesh conflict; CTD at startup → missing master or incompatible versions; CTD mid-game → script overload or animation conflict

**Stage 2 — Guided walkthrough (run simultaneously with Stage 1):**
1. Ask user: which mods were added or changed most recently?
2. Ask: does disabling the most recently added mod stop the crash?
3. If crash persists: binary disable test — disable half the mod list, test, narrow to the conflicting half
4. Ask: does the game provide a crash log? (Skyrim: %LOCALAPPDATA%\Skyrim Special Edition\crash logs\ if Crash Logger SKSE plugin installed; Fallout 4: Documents\My Games\Fallout4\)

**Stage 3 — Synthesizer step:**
Merge research synthesis and guided walkthrough output into one coherent plan:
- Specific culprit hypothesis (named mod or plugin, if narrowed)
- Recommended load order fix (move plugin X after plugin Y; add missing master; run LOOT)
- Verification step (launch game, confirm crash is gone)

This is in-turn structured reasoning (D-C4 schema) — NOT an Agent tool invocation.

**Default confidence tier:** MEDIUM (pattern match on conflict type; confirmed mod culprit elevates to HIGH)
**Runtime elevation rule:** If user confirms disabling a specific mod stops the crash AND $ver.isWin10 = true OR $ver.isWin11 = true: elevate to HIGH. State reason per D-13.

**Fix classification:** Tier 2 — load order file write (plugins.txt or loadorder.txt modification). `Copy-Item` backup to $env:TEMP\tier1-loadorder-[ts].bak required before write. Rollback pre-check via check-rollback.ps1 required.

**Rollback plan text (for approval gate):**
```
Rollback plan:
- Load order backup: the current plugins.txt (and loadorder.txt if present) will be copied to $env:TEMP\tier1-loadorder-[timestamp].bak and $env:TEMP\tier1-loadorder-lt-[timestamp].bak before any changes.
- To restore: Copy-Item "$env:TEMP\tier1-loadorder-[timestamp].bak" -Destination "<game_appdata_path>\plugins.txt" -Force
- Vortex users: Vortex manages plugins.txt internally — use Vortex's built-in "Restore backup" or revert profile instead of manually restoring this file.
- System Restore point: [mostRecentDate] ([pointAge_days] days ago) is the broader safety net.
```

**Change diff text (for approval gate, D-06 format):**
```
What changes: The load order file (plugins.txt and/or loadorder.txt) will be modified to resolve the conflict identified in diagnosis. Specific change: [plugin X moved after plugin Y / missing master added to load path / conflicting mod removed from active list].

Exact paths/keys/services: %LOCALAPPDATA%\[Game]\plugins.txt (game-specific path varies: Skyrim SE: %LOCALAPPDATA%\Skyrim Special Edition\; Fallout 4: %LOCALAPPDATA%\Fallout4\)

Time estimate: Under 1 minute

Restart required: No — load order takes effect on next game launch.
```

**Fix commands (canonical — escape hatch must match exactly):**
```powershell
# Step A: Capture current load order as rollback artifact BEFORE any change
$ts = Get-Date -f yyyyMMdd-HHmmss
$gamePath = "$env:LOCALAPPDATA\Skyrim Special Edition"  # substitute correct game path
$pluginsFile = "$gamePath\plugins.txt"
$loadorderFile = "$gamePath\loadorder.txt"

if (Test-Path $pluginsFile) {
    Copy-Item $pluginsFile "$env:TEMP\tier1-loadorder-$ts.bak" -Force
}
if (Test-Path $loadorderFile) {
    Copy-Item $loadorderFile "$env:TEMP\tier1-loadorder-lt-$ts.bak" -Force
}

# Step B: Verify backup artifacts exist before proceeding
Test-Path "$env:TEMP\tier1-loadorder-$ts.bak"
# HARD STOP if Test-Path returns False — do not proceed without verified backup

# Step C: Apply load order fix — example: move plugin to correct position
# Actual edit depends on diagnosis output. Method: read file, reorder, write back.
# If using Vortex or MO2: apply sort via LOOT integration in manager UI (preferred over manual edit)
# If manual: Get-Content → sort/reorder lines → Set-Content $pluginsFile
```

**Post-verification check:**
```powershell
# Verify backup artifacts exist
Test-Path "$env:TEMP\tier1-loadorder-*.bak"

# Verify plugins.txt was updated (check modification time)
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "(Get-Item '$env:LOCALAPPDATA\Skyrim Special Edition\plugins.txt').LastWriteTime"
```
Success: game launches without crash; backup artifacts confirmed at $env:TEMP\tier1-loadorder-[ts].bak.

**Post-fix explanation text (for UX-04):**
```
What was wrong: One or more mods were loading in the wrong order, causing a conflict. When two mods both modify the same game record (an NPC, a location, an item), the one that loads last "wins" — if the winner is the wrong one, the game crashes or behaves incorrectly.

Why it happened: Load order conflicts typically appear after adding a new mod that touches records already modified by an existing mod. Running LOOT automatically sets safe load order for most mods, but some conflicts require manual placement or a compatibility patch.

What changed: The load order file (plugins.txt) was updated to place the conflicting plugin(s) in the correct position. A backup of the previous load order was saved to %TEMP%\tier1-loadorder-[timestamp].bak.

Why the fix worked: With plugins loading in the correct order, the right mod "wins" each record conflict, and the crash condition is eliminated.

If something seems off later: Restore the previous load order from %TEMP%\tier1-loadorder-[timestamp].bak. If you use Vortex, the backup is also accessible via Vortex's profile revert. System Restore point from [mostRecentDate] is the broader safety net.
```

---

## Mod Safety Concern

**What this covers:** User concerned about mod safety — antivirus flagged a mod file, user uncertain about source trustworthiness, or mod from unofficial distribution channel. Applies structural checks to identify signature problems and obvious red flags.

**Trigger conditions:**
- User description: "antivirus flagged my mod", "is this mod safe?", "mod from unofficial source", concern about unsigned executables
- $unsignedExes contains files with Status = NotSigned, HashMismatch, or NotTrusted
- User downloaded mod from outside Nexus Mods / Steam Workshop / official distribution

**Diagnosis logic (apply to collected data):**
1. Run Get-AuthenticodeSignature on .exe and .dll files in mod staging area (already collected in $unsignedExes if DIAG-02 ran)
2. Map status values to actions:
   - **Valid** — signature intact, chains to trusted root. Safe from signature perspective.
   - **NotSigned** — no Authenticode signature. Flag with disclosure — not necessarily malicious but most legitimate mods are unsigned (modders rarely sign).
   - **HashMismatch** — file was modified after signing. HIGH risk flag — file may be tampered.
   - **NotTrusted** — certificate not trusted by Windows. Flag as potentially self-signed or expired certificate.
   - **UnknownError / Incompatible** — flag for review.
3. Check for extension mismatches: files named .dll with EXE magic bytes (PE header starting with MZ at offset 0 — detectable via `[System.IO.File]::ReadAllBytes($path)[0..1]` comparison), or .txt files with executable headers.
4. Check for known risky patterns: unsigned executables in mod root folders (not in subdirectories), scripts (.bat, .ps1, .vbs) in unexpected locations within the mod archive.

> **Honest disclosure:** These checks detect signature problems and obvious red flags. They cannot replace antivirus scanning or guarantee a mod is safe. A signed mod can still contain unwanted behavior, and an unsigned mod is not automatically dangerous — most game mods are unsigned. If your antivirus flagged this mod, consider the source reputation and community reports before overriding the warning.

**Default confidence tier:** MEDIUM (structural checks provide limited assurance; community reputation is a stronger signal but not automatable)
**Runtime elevation rule:** If $unsignedExes contains a file with Status = HashMismatch: elevate confidence in the risk assessment to HIGH. State reason per D-13.

**Fix classification:** Tier 1 — all checks are read-only (Get-AuthenticodeSignature, file header inspection). No system state change.

**Rollback plan text (for approval gate):**
```
Rollback plan:
- These checks are read-only — no system changes are made. Nothing to roll back.
- If you decide to remove the flagged mod: use your mod manager's remove/uninstall feature.
  Vortex: right-click → Remove. MO2: right-click → Remove Mod.
- System Restore point from [mostRecentDate] is available if any prior mod installation caused issues.
```

**Change diff text (for approval gate, D-06 format):**
```
What changes: Nothing. This is a read-only safety scan of mod files in the staging area.
Get-AuthenticodeSignature will check digital signatures; file headers will be inspected for
extension mismatches. No files are modified, moved, or deleted.

Exact paths/keys/services: Read access to files in mod staging area (e.g., %APPDATA%\Vortex\staging\)

Time estimate: Under 1 minute (depends on number of mod files)

Restart required: No
```

**Fix commands (canonical — escape hatch must match exactly):**
```powershell
# Step 1: Scan mod staging area for signature status
$staging = "$env:APPDATA\Vortex"  # substitute correct manager staging path
Get-ChildItem -Path $staging -Recurse -Include "*.exe","*.dll" -ErrorAction SilentlyContinue |
    ForEach-Object {
        $sig = Get-AuthenticodeSignature $_.FullName -ErrorAction SilentlyContinue
        [PSCustomObject]@{ Path = $_.FullName; Status = $sig.Status; Signer = $sig.SignerCertificate.Subject }
    } | ConvertTo-Json

# Step 2: Check for extension mismatches (EXE header in .dll files)
Get-ChildItem -Path $staging -Recurse -Include "*.dll","*.txt" -ErrorAction SilentlyContinue |
    ForEach-Object {
        $bytes = [System.IO.File]::ReadAllBytes($_.FullName)[0..1]
        if ($bytes[0] -eq 0x4D -and $bytes[1] -eq 0x5A) {
            [PSCustomObject]@{ File = $_.FullName; Warning = "PE header detected — possible extension mismatch" }
        }
    } | ConvertTo-Json
```

**Post-verification check:**
```powershell
# No verification needed — read-only scan. Review output for flagged files.
```
Success: scan completes; user has a clear list of flagged files with status explanations and honest disclosure about check limitations.

**Post-fix explanation text (for UX-04):**
```
What was checked: All .exe and .dll files in your mod staging area were scanned for digital signature status, and file headers were inspected for extension mismatches.

What the results mean: [summarize findings — e.g., "3 unsigned files found, all are typical unsigned mod DLLs; no HashMismatch or extension mismatches detected."]

Important context: These structural checks verify signatures and catch obvious red flags, but they cannot guarantee a mod is safe. Community reputation, download source, and your antivirus results are equally important signals.

If you're still concerned: Keep your antivirus active, download mods only from trusted sources (Nexus Mods, Steam Workshop, official mod sites), and check the mod's comment section for reports from other users before installing.
```

---

## Mod Install Failure

**What this covers:** Mod is installed in the mod manager but not active in the game — deployment didn't happen, game can't see the mod files, or mod files are in the wrong location. Applies when the mod manager shows the mod as installed but the game behaves as if it's not there.

**Trigger conditions:**
- User description: "mod not working", "game doesn't see my mod", "installed mod but nothing changed", mod appears in manager but not in game
- $modManagers shows manager installed but game directory missing expected mod files
- Mod manager shows deployment status as failed or pending

**Diagnosis logic (apply to collected data):**
1. Identify which mod manager is in use from $modManagers
2. Manager-specific deployment checks:
   - **Vortex:** Check deployment status — Vortex uses hardlinks/symlinks from staging to game directory. If deployment shows "Pending" or "Error", the fix is to purge and redeploy. Check $vortexLog for "Deploy" entries.
   - **MO2:** Uses a virtual filesystem (VFS) — mods only appear when game is launched through MO2. If user launched game directly (not through MO2), mods won't be visible. Check MO2 instance for correct game executable path.
   - **Steam Workshop:** Check subscription state — mod may show as subscribed but not downloaded. Verify files exist at steamapps\workshop\content\<AppId>\.
3. Check if mod requires specific load order position or master file dependency — cross-reference with Load Order Conflict section if applicable.
4. Check if mod files are in the correct location for the game (Data\ folder for Bethesda games, Mods\ folder for others).

**Default confidence tier:** MEDIUM (deployment state confirmation elevates to HIGH)
**Runtime elevation rule:** If $modManagers confirms manager AND $vortexLog or MO2 log contains a specific deployment error AND user confirms game is launched through the manager: elevate to HIGH. State reason per D-13.

**Fix classification:** Tier 1 for diagnostic checks (read manager state, check file locations). Tier 2 for redeployment (Vortex purge+deploy modifies game directory hardlinks). Rollback pre-check via check-rollback.ps1 required for Tier 2 gate.

**Rollback plan text (for approval gate):**
```
Rollback plan:
- Vortex redeployment: purge removes hardlinks from the game directory; redeploy recreates them.
  If something goes wrong, purge again — this removes all mod hardlinks from the game directory,
  returning it to vanilla state. Your mod files in staging are untouched.
- MO2 VFS: no persistent changes — mods appear only during MO2-launched sessions. Closing MO2
  or the game removes all VFS overlays.
- System Restore point from [mostRecentDate] is the broader safety net.
```

**Change diff text (for approval gate, D-06 format):**
```
What changes: Mod deployment will be refreshed. For Vortex: existing hardlinks in the game directory
will be purged and recreated. For MO2: VFS configuration will be verified and game launch path corrected
if needed.

Exact paths/keys/services: Vortex: <Game Data directory> hardlinks. MO2: instance profile configuration.

Time estimate: 1–5 minutes (depends on mod count)

Restart required: No — game restart is sufficient.
```

**Fix commands (canonical — escape hatch must match exactly):**
```powershell
# Vortex fix: Purge and redeploy
# Step 1: Open Vortex → Mods tab → click "Purge Mods" in toolbar
# Step 2: After purge completes → click "Deploy Mods" in toolbar
# Step 3: Check Vortex notification area for deployment errors

# MO2 fix: Verify game launch path
# Step 1: Open MO2 → select correct game profile in top-left dropdown
# Step 2: Verify executable path: click the gear icon next to "Run" → confirm path points to game .exe
# Step 3: Launch game through MO2's Run button (NOT through Steam or desktop shortcut)

# Steam Workshop fix: Force re-download
# Step 1: Open Steam → Library → right-click game → Properties → Installed Files → Verify integrity
# Step 2: If mod still missing: unsubscribe and resubscribe to the mod on Workshop page
```

**Post-verification check:**
```powershell
# Verify mod files are deployed to game directory
# (Substitute correct game data path)
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Test-Path '<GameDataDir>\<expected_mod_file>'"
```
Success: mod files present in game directory; game recognizes and loads the mod.

**Post-fix explanation text (for UX-04):**
```
What was wrong: The mod was installed in your mod manager but wasn't properly deployed to the game directory. The game couldn't see the mod files because they hadn't been linked or copied to where the game looks for them.

Why it happened: [Vortex: Deployment was interrupted or failed — hardlinks from the staging folder to the game directory were missing or broken. / MO2: The game was launched directly instead of through MO2, which meant the virtual filesystem wasn't active. / Steam Workshop: Download was incomplete or subscription state was out of sync.]

What changed: [Vortex: Mod hardlinks were recreated from staging to the game directory. / MO2: Game launch path was corrected to go through MO2's virtual filesystem. / Steam Workshop: Mod files were re-downloaded and placed in the correct Workshop directory.]

Why the fix worked: The mod files are now in the location where the game expects to find them. On next launch, the game will detect and load the mod normally.

If something seems off later: Vortex users can purge mods to return the game directory to vanilla. MO2 users can simply close MO2 to remove VFS overlays. System Restore point from [mostRecentDate] is the broader safety net.
```

---

## DIAG-02 Targeted Collection

Post-routing collection commands for Gaming Mods domain. Invoked by SKILL.md after Step 3b routes to gaming-mods.md. Each command runs via Bash tool. Soft-fail rule: if any command fails or returns empty, set variable = "" and continue.

```powershell
# 1. Mod manager presence detection
$managers = @()
if (Test-Path "$env:APPDATA\Vortex") { $managers += "Vortex: $env:APPDATA\Vortex" }
if (Test-Path "$env:LOCALAPPDATA\ModOrganizer") { $managers += "MO2 (instanced): $env:LOCALAPPDATA\ModOrganizer" }
if (Test-Path "$env:LOCALAPPDATA\NexusModManager") { $managers += "NMM: $env:LOCALAPPDATA\NexusModManager" }
$modManagers = $managers | ConvertTo-Json
# soft-fail: if empty, $modManagers = ""

# 2. Recent Vortex log (last 100 lines — high-signal for deployment errors)
$vortexLog = ""
$vortexLogPath = "$env:APPDATA\Vortex\logs\main.log"
if (Test-Path $vortexLogPath) {
    $vortexLog = Get-Content $vortexLogPath -Tail 100 -ErrorAction SilentlyContinue
}
# soft-fail: if no Vortex or log missing, $vortexLog = ""

# 3. Unsigned executable scan in Vortex staging area
$unsignedExes = ""
$staging = "$env:APPDATA\Vortex"
if (Test-Path $staging) {
    $unsignedExes = Get-ChildItem -Path $staging -Recurse -Include "*.exe","*.dll" -ErrorAction SilentlyContinue |
        ForEach-Object { Get-AuthenticodeSignature $_.FullName -ErrorAction SilentlyContinue } |
        Where-Object { $_.Status -ne 'Valid' } |
        Select-Object Path, Status |
        ConvertTo-Json
}
# soft-fail: if no staging area or scan fails, $unsignedExes = ""
```

---

*Phase 4 output. Consumed by SKILL.md and governs routing, diagnosis, and fix proposals for the Gaming Mods problem domain.*
*Do not add UX copy (approval gate text, escape hatch instructions, refusal message wording) to this file — those belong in SKILL.md.*
