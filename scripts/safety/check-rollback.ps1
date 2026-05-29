#Requires -Version 5.1
<#
.SYNOPSIS
    Tier1 rollback pre-check script. Checks VSS/System Restore state before Tier 2+ operations.

.DESCRIPTION
    Outputs a single-line JSON object to stdout. All fields are always present.
    SKILL.md captures output with: $result = & "$scriptPath" | ConvertFrom-Json

    JSON fields:
      scriptVersion     string   Always "1.0"
      isAdmin           bool     True if running as administrator
      srEnabled         bool     True if System Restore is enabled (RPSessionInterval >= 1)
      hasRestorePoints  bool     True if at least one restore point exists (admin only)
      mostRecentDate    string   ISO date of newest restore point, or null
      pointAge_days     int      Days since newest restore point, or null
      createdNewPoint   bool     True if Checkpoint-Computer ran successfully this call
      createError       string   Error message if Checkpoint-Computer failed, or null

.PARAMETER CreateIfAbsent
    If set, attempt to create a restore point when srEnabled=true but hasRestorePoints=false.
    Requires admin elevation. Silently skipped if not elevated.

.NOTES
    PowerShell 5.1 only. No external modules. No admin required for srEnabled check.
    Elevation required for: Get-ComputerRestorePoint, Checkpoint-Computer.
    Invoke from SKILL.md as: $check = & "$PSScriptRoot\..\..\scripts\safety\check-rollback.ps1" | ConvertFrom-Json
#>

param(
    [switch]$CreateIfAbsent
)

Set-StrictMode -Off
$ErrorActionPreference = 'SilentlyContinue'

# ── Step 1: Elevation detection (ALWAYS FIRST) ───────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

# ── Step 2: System Restore enabled check (non-admin path — registry) ─────────
# srEnabled: DisableSR = 0 (or absent) AND RPSessionInterval >= 1.
# DisableSR = 1 means SR is explicitly disabled — RPSessionInterval alone is not sufficient.
$srKey = Get-ItemProperty `
    'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' `
    -ErrorAction SilentlyContinue
$srDisabled = ($null -ne $srKey -and $srKey.DisableSR -eq 1)
$srEnabled  = (-not $srDisabled -and $null -ne $srKey -and $srKey.RPSessionInterval -ge 1)

# ── Step 3: Restore points (admin required) ───────────────────────────────────
$hasRestorePoints = $false
$mostRecentDate    = $null
$pointAge_days     = $null
$createdNewPoint   = $false
$createError       = $null

if ($isAdmin -and $srEnabled) {
    $points = Get-ComputerRestorePoint -ErrorAction SilentlyContinue

    if ($null -ne $points -and @($points).Count -gt 0) {
        $hasRestorePoints = $true
        $newest = @($points) | Sort-Object CreationTime -Descending | Select-Object -First 1
        # CreationTime is a WMI datetime string — MUST convert before arithmetic.
        # Use the instance method form shown in Microsoft's official Get-ComputerRestorePoint example.
        # Do NOT call .ToString() or subtract directly on $newest.CreationTime — it is NOT a .NET DateTime.
        $newestDt = $newest.ConvertToDateTime($newest.CreationTime)
        $mostRecentDate = $newestDt.ToString('yyyy-MM-dd')
        $pointAge_days  = [int]((Get-Date) - $newestDt).TotalDays
    }

    # Offer to create a restore point if none exist and caller requested it
    if (-not $hasRestorePoints -and $CreateIfAbsent) {
        try {
            Checkpoint-Computer -Description 'Tier1-pre-fix' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
            # Do NOT trust Checkpoint-Computer's implicit success — throttle emits a non-terminating
            # warning (not a terminating error) and creates nothing. -ErrorAction Stop cannot catch it.
            # Re-query to confirm a point was actually created.
            $verifyPoints = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
            $verifyNewest = @($verifyPoints) | Sort-Object CreationTime -Descending | Select-Object -First 1
            if ($null -ne $verifyNewest) {
                $verifiedDt       = $verifyNewest.ConvertToDateTime($verifyNewest.CreationTime)
                $createdNewPoint  = $true
                $hasRestorePoints = $true
                $mostRecentDate   = $verifiedDt.ToString('yyyy-MM-dd')
                $pointAge_days    = [int]((Get-Date) - $verifiedDt).TotalDays
            } else {
                # Throttled: Checkpoint-Computer returned without error but created no point.
                $createError = 'Checkpoint-Computer call succeeded but no restore point found. ' +
                               'Windows may be throttling restore point creation (SystemRestorePointCreationFrequency). ' +
                               'Try again after 24 hours, or create a restore point manually via System Properties.'
            }
        }
        catch {
            $createError = $_.Exception.Message
        }
    }
}

# ── Output JSON (always, all paths) ──────────────────────────────────────────
[ordered]@{
    scriptVersion    = '1.0'
    isAdmin          = $isAdmin
    srEnabled        = $srEnabled
    hasRestorePoints = $hasRestorePoints
    mostRecentDate   = $mostRecentDate
    pointAge_days    = $pointAge_days
    createdNewPoint  = $createdNewPoint
    createError      = $createError
} | ConvertTo-Json -Compress
