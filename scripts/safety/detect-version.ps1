#Requires -Version 5.1
<#
.SYNOPSIS
    Tier1 Windows version/edition/architecture detection script.

.DESCRIPTION
    Outputs a single-line JSON object to stdout. All fields are always present.
    SKILL.md captures output with: $ver = & "$scriptPath" | ConvertFrom-Json

    JSON fields:
      scriptVersion     string   Always "1.0"
      osVersion         string   e.g. "10.0.22621" — null if CIM fails
      osBuildNumber     string   e.g. "22621" — null if CIM fails
      osCaption         string   e.g. "Microsoft Windows 11 Pro" — null if CIM fails
      osArchitecture    string   "64-bit" or "ARM 64-bit" — null if CIM fails
      osSku             int      OperatingSystemSKU numeric code — null if CIM fails
      isClientOs        bool     True if ProductType=1 (client OS, not Server/DC)
      isWin10           bool     Build >= 10240 and < 22000 (client OS only)
      isWin11           bool     Build >= 22000 (client OS only)
      isSMode           bool     SkuPolicyRequired registry key = 1 (NOT EditionID)
      isLTSC            bool     SKU 125 or 126, OR caption contains "LTSC"
      isLTSC_confident  bool     False when LTSC determined by caption fallback only
      isHome            bool     SKU = 101
      isPro             bool     SKU = 48 or 49
      executionPolicy   string   Effective (highest-precedence) execution policy string
      detectionErrors   array    List of non-fatal errors encountered

.NOTES
    PowerShell 5.1 only. No admin required. No external modules.
    Uses CIM (not WMI/DCOM) for Win32_OperatingSystem query.

    S MODE DETECTION: Uses ONLY SkuPolicyRequired registry key.
    DO NOT use Get-WindowsEdition or check EditionID for S Mode —
    LTSC variants can have an '-S' suffix in EditionID without being S Mode.
    (See: github.com/anthropics/claude-code/issues/28066)

    LTSC SKU CODES: Values 125 and 126 are inferred from WinNT.h constants.
    They are not in the official OperatingSystemSKU enum documentation.
    The caption-based fallback catches cases where SKU is wrong.

    Invoke from SKILL.md as:
      $ver = & "$PSScriptRoot\..\..\scripts\safety\detect-version.ps1" | ConvertFrom-Json
    Run this BEFORE proposing any fix — SKILL.md must check version compatibility first.
#>

Set-StrictMode -Off
$ErrorActionPreference = 'SilentlyContinue'

$detectionErrors = @()

# ── Step 1: CIM query for OS properties (no admin required) ──────────────────
# Use CIM (WS-Man), not WMI (DCOM) — CIM is the modern path even in PS 5.1.
$os = $null
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
}
catch {
    $detectionErrors += "Win32_OperatingSystem CIM query failed: $($_.Exception.Message)"
}

$osVersion      = $null
$osBuildNumber  = $null
$osCaption      = $null
$osArchitecture = $null
$osSku          = $null
$isClientOs     = $false
$isWin10        = $false
$isWin11        = $false
$isHome         = $false
$isPro          = $false
$isLTSC         = $false
$isLTSC_confident = $true

if ($null -ne $os) {
    $osVersion      = $os.Version
    $osBuildNumber  = $os.BuildNumber
    $osCaption      = $os.Caption
    $osArchitecture = $os.OSArchitecture   # "64-bit" or "ARM 64-bit"
    $osSku          = [int]$os.OperatingSystemSKU

    # Win11: first build is 22000 (21H2); Win10: 10240 (1507) through 19045 (22H2)
    # ProductType: 1=client, 2=domain controller, 3=server. Gate on client to avoid
    # misclassifying Server 2022 (build 20348) as Win10 or Server 2025 (26100) as Win11.
    $buildInt    = [int]$os.BuildNumber
    $isClientOs  = ($os.ProductType -eq 1)
    $isWin11     = ($isClientOs -and $buildInt -ge 22000)
    $isWin10     = ($isClientOs -and $buildInt -ge 10240 -and $buildInt -lt 22000)

    # Edition from SKU code
    # SKU 101 = Home; 48 = Pro; 49 = Pro N (European N variant)
    # Home family: 101 (Home), 100 (Home Single Language), 98 (Home N), 99 (Home Country Specific)
    $isHome = ($osSku -eq 101 -or $osSku -eq 100 -or $osSku -eq 98 -or $osSku -eq 99)

    # Pro family: 48 (Pro), 49 (Pro N), 161 (Pro Workstation), 164 (Pro for Education), 165 (Pro for Education N)
    $isPro  = ($osSku -eq 48 -or $osSku -eq 49 -or $osSku -eq 161 -or $osSku -eq 164 -or $osSku -eq 165)

    # LTSC: SKU 125 (Enterprise LTSC) and 126 (LTSC) — inferred from WinNT.h, not official enum.
    # Fallback: caption string match (covers unknown future LTSC SKU codes).
    $isLTSC_bySku     = ($osSku -eq 125 -or $osSku -eq 126)
    $isLTSC_byCaption = ($osCaption -match 'LTSC')
    $isLTSC           = $isLTSC_bySku -or $isLTSC_byCaption
    $isLTSC_confident = $isLTSC_bySku   # false = LTSC detected only by caption (lower confidence)
}

# ── Step 2: S Mode detection (SkuPolicyRequired — NOT EditionID) ─────────────
# CRITICAL: Do NOT use Get-WindowsEdition or check EditionID for S Mode.
# LTSC variants can have '-S' suffix in EditionID without being S Mode.
# SkuPolicyRequired = 1 means S Mode is active; 0 or absent means not S Mode.
$sModeKey = Get-ItemProperty `
    'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' `
    -ErrorAction SilentlyContinue
$isSMode = ($null -ne $sModeKey -and $sModeKey.SkuPolicyRequired -eq 1)

# ── Step 3: Execution policy (effective policy — highest-precedence scope) ────
$execPolicy = $null
try {
    # Get-ExecutionPolicy without -Scope returns the effective (highest-precedence) policy.
    # This accounts for MachinePolicy/UserPolicy GPO overrides that LocalMachine scope misses.
    $execPolicy = (Get-ExecutionPolicy -ErrorAction Stop).ToString()
}
catch {
    $detectionErrors += "ExecutionPolicy query failed: $($_.Exception.Message)"
}

# ── Output JSON (always, all paths) ──────────────────────────────────────────
[ordered]@{
    scriptVersion     = '1.0'
    osVersion         = $osVersion
    osBuildNumber     = $osBuildNumber
    osCaption         = $osCaption
    osArchitecture    = $osArchitecture
    osSku             = $osSku
    isClientOs        = $isClientOs
    isWin10           = $isWin10
    isWin11           = $isWin11
    isSMode           = $isSMode
    isLTSC            = $isLTSC
    isLTSC_confident  = $isLTSC_confident
    isHome            = $isHome
    isPro             = $isPro
    executionPolicy   = $execPolicy
    detectionErrors   = $detectionErrors
} | ConvertTo-Json -Compress
