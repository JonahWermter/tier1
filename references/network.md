# Network/Connectivity Domain Reference

**Version:** 1.0
**Updated:** 2026-05-21

> **Loading Note:** This file is NOT automatically in context. SKILL.md must explicitly load it via
> the Read tool at session start. There is no `references:` frontmatter field in Claude Code SKILL.md.
> See SKILL.md Session Start section for the exact Read tool call.

---

## Diagnostic Methodology

Mental model for the 4 worked examples below. Use worked examples when evidence matches. Use this section when it doesn't.

### When evidence matches

Match collected data to a section via SKILL.md Step 3b routing. Apply diagnosis logic against ($adapterState, $dnsConfig, $ipConfig, $wifiProfiles). Use default confidence tier as floor. Apply runtime elevation rule. Present fix classification, rollback plan, and change diff as documented.

Match from data — description is secondary signal only.

### When no example matches (D-RT3)

State available signals and absent signals. MEDIUM confidence if one signal points at a cause; LOW if ambiguous. Propose most conservative fix (prefer read-only diagnostics). If no safe fix: tell user what to tell a technician. MEDIUM + Tier 1 diagnostic step beats refusing to engage.

### Evidence-collection priorities

- **$adapterState** — adapter status, link speed. "Disabled"/"Not Present" → Adapter Reset section.
- **$dnsConfig** — DNS servers per interface. Primary for DNS resolution failure diagnosis.
- **$ipConfig** — IP addresses, gateways, prefix lengths. APIPA range (169.254.x.x) → IP Configuration Conflict.
- **$wifiProfiles** — saved Wi-Fi profiles. Required for Wi-Fi association failure diagnosis.

### Tier discipline

Before any fix proposal, apply the correct tier classification:

| Operation | Tier | Rationale | Rollback Artifact |
|-----------|------|-----------|-------------------|
| `ipconfig /flushdns` | Tier 1 | DNS cache clear — auto-repopulated on next query; no persistent state change | None required |
| `Get-NetAdapter`, `Get-DnsClientServerAddress`, `Get-NetIPConfiguration` | Tier 1 | Read-only diagnostic collection | None |
| `netsh wlan show profiles` | Tier 1 | Read-only Wi-Fi profile listing | None |
| `ipconfig /release`, `ipconfig /renew` | Tier 1 | DHCP lease cycle — DHCP client re-requests; no persistent config change | None |
| `netsh winsock reset` | Tier 2 | Removes LSP catalog entries; reboot required; VPN/security software LSPs may be removed | `netsh winsock dump > $env:TEMP\tier1-winsock-[ts].txt` before reset |
| `netsh int ip reset` | Tier 2 | Overwrites TCP/IP registry keys; reboot required; static IP configuration will be destroyed | `Get-NetIPConfiguration \| ConvertTo-Json > $env:TEMP\tier1-netconfig-[ts].json` before reset |

Never present a Tier 2 gate without the rollback pre-check (check-rollback.ps1) running first and passing.

### Graduated cascade principle (D-N1)

Apply when basic IP/DNS fixes don't resolve. NEVER bundled — each gate is separate:

| Gate | Command | Tier | Condition to Present |
|------|---------|------|----------------------|
| 1 — DNS flush | `ipconfig /flushdns` | Tier 1 | Always first; required before any Tier 2 |
| 2 — Winsock reset | `netsh winsock reset` | Tier 2 | Only if Gate 1 did not resolve |
| 3 — TCP/IP reset | `netsh int ip reset` | Tier 2 | Only if Gate 2 did not resolve; last resort |

Each gate requires individual user approval. Gate N+1 never presented unless Gate N failed. Never bundle.

---

## IP Configuration Conflict

**What this covers:** APIPA self-assigned addresses (169.254.x.x), "Limited connectivity", DHCP lease failure, inability to ping default gateway.

**Trigger conditions:**
- $ipConfig shows 169.254.x.x (APIPA) or 0.0.0.0 (no lease)
- User: "Limited connectivity", "No internet access", yellow triangle on network icon
- Gateway unreachable while adapter shows Connected

**Diagnosis logic (apply to collected data):**
1. Check $ipConfig for 169.254.x.x or 0.0.0.0 — confirms DHCP lease failure
2. Check DHCP service: `Get-Service -Name Dhcp | Select-Object Status`
3. DHCP stopped + APIPA detected → service failure is root cause; elevate to HIGH
4. DHCP running + APIPA present → DHCP server not reachable or lease exhaustion; renew to test
5. Check gateway: `Test-NetConnection -ComputerName <GatewayAddress> -InformationLevel Quiet`
6. Gateway unreachable after renew → upstream issue (router/DHCP server); disclose; client-side fixes may not resolve

**Default confidence tier:** MEDIUM (APIPA is a named pattern; DHCP service state confirmation elevates to HIGH)
**Runtime elevation rule:** If `$ipConfig` shows APIPA address AND `Get-Service -Name Dhcp` returns Status = Stopped AND `$ver.isWin10 = true` OR `$ver.isWin11 = true`: elevate to HIGH. State reason per D-13.

**Fix classification:** Tier 1 for `ipconfig /release` + `ipconfig /renew` (DHCP lease cycle — no persistent state change). Escalates to Tier 2 graduated cascade if DHCP renew does not restore connectivity.

**Rollback plan text (for approval gate):**
```
Rollback plan:
ipconfig /release and /renew cycle the DHCP lease — a request to the router for a new IP address.
No system state is permanently modified. If renew fails, adapter retains its current address.
Self-reverting — nothing to undo.
```

**Change diff text (for approval gate, D-06 format):**
```
What changes: IP lease released; fresh DHCP request sent. New IP from router if DHCP reachable.

Exact paths/keys/services: IP address on adapter (DHCP lease only — no registry or file changes)

Time estimate: Under 30 seconds

Restart required: No
```

**Fix commands (canonical — escape hatch must match exactly):**
```powershell
# If DHCP client service was stopped, start it first:
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Start-Service -Name Dhcp"

# Release and renew DHCP lease:
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "ipconfig /release"
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "ipconfig /renew"
```

**Post-verification check:**
```powershell
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Get-NetIPConfiguration | Select-Object InterfaceAlias, IPv4Address, IPv4DefaultGateway | ConvertTo-Json"
```
Success: IPv4 address is routable (not 169.254.x.x or 0.0.0.0) and default gateway is populated.

If APIPA persists: DHCP server unreachable (router/modem issue) — disclose; propose DNS flush gate per graduated cascade.

**Post-fix explanation text (for UX-04):**
```
What was wrong: No valid IP from router — computer self-assigned a 169.254.x.x (APIPA) address,
which only works for local device-to-device communication, not internet access.

Why it happened: Router DHCP temporarily unavailable, adapter connected before router finished
booting, or a previous lease expired and the renewal failed silently.

What changed: Stale IP lease released; fresh DHCP request sent. Router issued a valid IP address,
gateway, and DNS server settings.

Why the fix worked: Routable IP address now issued by router — traffic flows normally through gateway.

If something seems off later: If APIPA returns after reboot, check router's DHCP lease table. No
System Restore point required — this fix modifies no persistent system state.
```

---

## DNS Resolution Failure

**What this covers:** Valid IP + reachable gateway, but DNS name resolution fails — websites don't load, browser shows DNS_PROBE_FINISHED_NXDOMAIN, nslookup fails.

**Trigger conditions:**
- User: "websites won't load but ping by IP works", DNS_PROBE_FINISHED_NXDOMAIN, nslookup fails
- `Resolve-DnsName google.com` fails but `Test-NetConnection 8.8.8.8 -Port 80` succeeds
- $dnsConfig shows unreachable or misconfigured DNS servers
- $ipConfig shows valid routable IP and gateway (DNS-layer problem, not IP-layer)

**Diagnosis logic (apply to collected data):**
1. Confirm IP layer: `Test-NetConnection -ComputerName 8.8.8.8 -Port 80 -InformationLevel Quiet` — failure → re-route to IP Configuration Conflict
2. Test DNS: `Resolve-DnsName google.com -ErrorAction SilentlyContinue` — failure with working IP confirms DNS problem
3. Check DNS servers: `Get-DnsClientServerAddress | Where-Object {$_.AddressFamily -eq 2} | Select-Object InterfaceAlias, ServerAddresses`
4. Test DNS reachability: `Test-NetConnection -ComputerName <DNSServer> -Port 53 -InformationLevel Quiet`
5. DNS unreachable → upstream issue; propose public DNS (8.8.8.8 / 1.1.1.1) as diagnostic test
6. DNS reachable but resolution fails → stale cache most likely; proceed to flush (Gate 1)

**Default confidence tier:** MEDIUM (named pattern; confirming resolution test or event data elevates to HIGH)
**Runtime elevation rule:** If `Resolve-DnsName google.com` fails AND `Test-NetConnection 8.8.8.8 -Port 80` succeeds (confirming DNS-layer failure on working IP) AND `$ver.isWin10 = true` OR `$ver.isWin11 = true`: elevate to HIGH. State reason per D-13.

**Fix classification:** Tier 1 for `ipconfig /flushdns` (auto-repopulated; no persistent state change). If unresolved: graduated cascade — Gate 2 Winsock reset (Tier 2), Gate 3 TCP/IP reset (Tier 2). Each gate separate, each with own rollback artifact.

**Rollback plan text (for approval gate — DNS flush gate):**
```
Rollback plan:
ipconfig /flushdns clears the DNS resolver cache. Cache is automatically rebuilt from DNS queries as
you browse — no persistent state change. Nothing to undo. DNS entries are transient by design.
```

**Change diff text (for approval gate — DNS flush, D-06 format):**
```
What changes: Local DNS resolver cache cleared. Stale or corrupt cached entries removed. Windows
performs fresh DNS lookups for each hostname going forward.

Exact paths/keys/services: DNS resolver cache (in-memory only — no files or registry keys modified)

Time estimate: Under 5 seconds

Restart required: No
```

**Fix commands (canonical — DNS flush gate):**
```powershell
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "ipconfig /flushdns"
```

**Post-verification check (DNS flush gate):**
```powershell
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Resolve-DnsName google.com -ErrorAction SilentlyContinue | Select-Object Name, IPAddress | ConvertTo-Json"
```
Success: Resolve-DnsName returns IP addresses. If still fails: present Gate 2 (Winsock reset) — own approval gate. Do NOT bundle.

---

### Gate 2: Winsock Reset (if DNS flush did not resolve)

**Fix classification:** Tier 2 — removes LSP entries from Winsock catalog; reboot required; VPN/security software LSPs removed (may need reinstall). Rollback pre-check via check-rollback.ps1 required.

**Rollback plan text (for approval gate — Winsock reset gate):**
```
Rollback plan:
Winsock catalog exported before reset to: $env:TEMP\tier1-winsock-[timestamp].txt
This file is a re-executable script — restore by running it from an elevated PowerShell prompt.

Windows also auto-saves the pre-reset catalog to:
  HKLM\SYSTEM\CurrentControlSet\Services\WinSock2\Parameters\Protocol_Catalog_Before_Reset

System Restore point [mostRecentDate] is the broader safety net.

If VPN or security software is installed, it may need reinstalling — its LSP entries will be removed.
```

**Change diff text (for approval gate — Winsock reset, D-06 format):**
```
What changes: The Windows Sockets (Winsock) catalog will be reset to its default state. Layered
Service Provider (LSP) entries injected by third-party software (VPN clients, security software,
network filters) will be removed.

Exact paths/keys/services: Winsock catalog in registry under
HKLM\SYSTEM\CurrentControlSet\Services\WinSock2\Parameters

Time estimate: Under 1 minute

Restart required: YES — Winsock reset takes effect after reboot. VPN and security software LSP
entries may be removed and may require reinstallation after reboot.
```

**Fix commands (canonical — Winsock reset gate):**
```powershell
# Capture Winsock catalog as rollback artifact (MUST run before reset):
$ts = Get-Date -f yyyyMMdd-HHmmss
netsh winsock dump | Out-File "$env:TEMP\tier1-winsock-$ts.txt"

# Reset Winsock catalog:
netsh winsock reset
```

**Post-verification check (Winsock reset gate — after reboot):**
```powershell
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Resolve-DnsName google.com -ErrorAction SilentlyContinue | Select-Object Name, IPAddress | ConvertTo-Json"
```
Success: Resolve-DnsName returns IP addresses. If still fails: present Gate 3 (TCP/IP reset) — own approval gate. Do NOT bundle.

**Post-fix explanation text (DNS resolution failure — covers flush through Winsock reset):**
```
What was wrong: DNS name resolution failing — computer could not convert hostnames to IP addresses.
Network connection was working; only DNS was broken.

Why it happened: Stale or corrupt DNS cache (resolved by flush) or corrupt Winsock catalog — a
registry-level table controlling how apps access the network stack. VPNs, firewalls, or malware
can corrupt LSP entries in the Winsock catalog.

What changed: DNS cache cleared (Gate 1). If unresolved: Winsock catalog reset to clean default
state (Gate 2), removing corrupt or foreign LSP entries.

Why the fix worked: Clean Winsock catalog means DNS queries travel through standard network stack
without interference from corrupt LSP filters.

If something seems off later: Winsock backup at $env:TEMP\tier1-winsock-[timestamp].txt. If VPN
or security software stopped working: reinstall it — LSPs re-register on install. System Restore
point from [mostRecentDate] is the broader safety net.
```

---

## Adapter Reset Needed

**What this covers:** Adapter stuck in error/disabled state or driver fault. Get-NetAdapter shows Status = "Disabled" or "Not Present". Complete network unavailability.

**Trigger conditions:**
- $adapterState shows Status = "Disabled" or "Not Present" for an expected adapter
- Get-PnpDevice shows an error code (ProblemCode > 0) for a network adapter
- User description: "network adapter disappeared", "adapter shows disabled", "can't find network adapter in Device Manager"
- All connectivity fails with no IP address — $ipConfig shows no adapters with active addresses

**Diagnosis logic (apply to collected data):**
1. $adapterState Status = "Disabled" → manually disabled or driver event; Enable-NetAdapter is first fix
2. $adapterState Status = "Not Present" → driver not binding; check for recent driver update
3. Check driver errors: `Get-PnpDevice -Class Net | Where-Object {$_.ProblemCode -gt 0} | Select-Object FriendlyName, InstanceId, ProblemCode`
4. ProblemCode > 0 + recent driver update in $driverList → driver rollback via Device Manager
5. No recent driver change + "Not Present" → driver reinstall; check Device Manager for error-flagged adapter
6. Disabled + no error code → re-enable is sufficient

**Default confidence tier:** MEDIUM (adapter disabled with no error code is HIGH-confidence; driver fault with error code is MEDIUM until driver history is checked)
**Runtime elevation rule:** If $adapterState shows Status = "Disabled" AND no ProblemCode error (ProblemCode = 0 or absent) AND `$ver.isWin10 = true` OR `$ver.isWin11 = true`: elevate to HIGH — clean disable with no fault is unambiguous. State reason per D-13.

**Fix classification:** Tier 1 for `Enable-NetAdapter` (no persistent state change; reversible). Tier 2 for driver rollback (modifies driver bindings; rollback artifact required; check-rollback.ps1 required).

**Rollback plan text (for approval gate — Enable-NetAdapter):**
```
Rollback plan:
Enable-NetAdapter re-enables a disabled adapter. To reverse: Settings → Network & Internet →
Change adapter options → right-click → Disable. Or: Disable-NetAdapter -Name "<AdapterName>"
-Confirm:$false from an elevated prompt. No files or registry keys modified.
```

**Change diff text (for approval gate — Enable-NetAdapter, D-06 format):**
```
What changes: Disabled adapter re-enabled; Windows reinitializes and requests a DHCP lease.

Exact paths/keys/services: Network adapter enable state (adapter: [AdapterName])

Time estimate: Under 30 seconds

Restart required: No
```

**Fix commands (canonical — escape hatch must match exactly):**
```powershell
# Re-enable disabled adapter (Tier 1):
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Enable-NetAdapter -Name '<AdapterName>' -Confirm:`$false"

# Driver rollback (Tier 2 — only if ProblemCode confirmed; capture artifact BEFORE rollback):
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Get-PnpDevice -Class Net | Where-Object {`$_.ProblemCode -gt 0} | Select-Object FriendlyName, InstanceId, ProblemCode | ConvertTo-Json | Out-File `"`$env:TEMP\tier1-adapter-driverinfo-$(Get-Date -f yyyyMMdd-HHmmss).txt`""
# Device Manager → Network Adapters → right-click → Properties → Driver → Roll Back Driver
```

**Post-verification check:**
```powershell
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Get-NetAdapter | Select-Object Name, Status, InterfaceDescription | ConvertTo-Json"
```
Success: target adapter shows Status = "Up" or "Connected".

**Post-fix explanation text (for UX-04):**
```
What was wrong: Network adapter in disabled or error state — no traffic possible.

Why it happened: Adapter disabled manually (Device Manager), by a driver error after Windows
Update, or by a fault detected during startup. Driver fault = driver encountered a problem;
Windows disabled adapter as a protective measure.

What changed: Adapter re-enabled; Windows reinitializes and requests a DHCP lease. If driver
rollback performed: faulty update replaced with previous working version.

Why the fix worked: Re-enabling restores hardware access. Rollback removes the faulty driver.

If something seems off later: If adapter disables again after reboot, driver is unstable — check
Windows Update or use manufacturer's driver directly. Driver info backup:
$env:TEMP\tier1-adapter-driverinfo-[timestamp].txt.
```

---

## Wi-Fi Association Failure

**What this covers:** Wi-Fi repeatedly drops, fails to associate with a known network, or shows auth failures where password is ruled out. Adapter is functional but connection is unstable.

**Trigger conditions:**
- User description: "Wi-Fi keeps disconnecting", "won't connect to my network", "connects then immediately drops", "authentication failed but password is correct"
- $adapterState shows Wi-Fi adapter Status = "Up" but no gateway reachable, or Status cycling between Up/Disconnected
- $wifiProfiles shows the target network profile exists but connection fails
- $ipConfig shows APIPA on the Wi-Fi adapter despite the network being in range

**Diagnosis logic (apply to collected data):**
1. Confirm password not the issue — ask user to verify before proposing profile deletion
2. Check saved profile: `netsh wlan show profiles name="<SSID>" key=clear` — reveals stored password + security type; compare with AP
3. Auth type mismatch: WPA2 profile stored but AP now requires WPA3 → confirm AP settings with user
4. Signal check: `netsh wlan show interfaces` — "Signal" below 30% → physical/AP-side problem
5. Password correct + profile exists + auth fails → delete and re-add profile (Tier 1)
6. Disclosure: AP-side issues (channel, security mismatch, firmware, interference) may be involved. Client-side fixes cover profile corruption and auth mismatches only. AP-side → escalate to network admin.

**Default confidence tier:** MEDIUM — Wi-Fi issues often involve AP-side configuration that cannot be diagnosed from the client alone. Do not overclaim.
**Runtime elevation rule:** If `netsh wlan show interfaces` shows an authentication failure AND the saved profile password is confirmed correct by the user AND `$ver.isWin10 = true` OR `$ver.isWin11 = true`: elevate to HIGH for profile deletion fix. State reason per D-13.

**Fix classification:** Tier 1 for profile deletion + reconnect (profile re-added by reconnecting; no state change). Escalates to graduated cascade (Tier 2) if unresolved and full connectivity broken.

**Rollback plan text (for approval gate — profile deletion):**
```
Rollback plan:
Deleting the Wi-Fi profile removes saved password and connection settings. To restore: reconnect
and re-enter the password — Windows creates a new profile automatically.
To reveal saved password before deleting: netsh wlan show profiles name="<SSID>" key=clear
No system files or registry keys outside the WLAN profile store are modified.
```

**Change diff text (for approval gate — profile deletion, D-06 format):**
```
What changes: Saved Wi-Fi profile for "<SSID>" deleted. Stored password, security type, and
connection settings removed. Re-enter password to reconnect.

Exact paths/keys/services: Wi-Fi profile store (C:\ProgramData\Microsoft\Wlansvc\Profiles\Interfaces\)

Time estimate: Under 5 seconds

Restart required: No
```

**Fix commands (canonical — escape hatch must match exactly):**
```powershell
# Optional: reveal saved password before deletion
netsh wlan show profiles name="<SSID>" key=clear

# Delete the profile
netsh wlan delete profile name="<SSID>"

# User reconnects via Wi-Fi UI and re-enters password
```

**Post-verification check:**
```powershell
netsh wlan show interfaces
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Get-NetIPConfiguration | Where-Object {`$_.InterfaceAlias -like '*Wi-Fi*' -or `$_.InterfaceAlias -like '*Wireless*'} | Select-Object InterfaceAlias, IPv4Address | ConvertTo-Json"
```
Success: "State" = connected, SSID matches, IPv4 address is routable (not APIPA).

**Post-fix explanation text (for UX-04):**
```
What was wrong: Saved Wi-Fi profile had corrupt, mismatched, or outdated configuration.
Authentication failed because stored security type or cached credentials didn't match the AP.

Why it happened: Profiles go stale when AP security settings change (WPA2→WPA3 upgrade), router
is replaced, or Windows profile state gets out of sync after repeated failed attempts.

What changed: Stale profile deleted; fresh profile created on reconnect with current AP settings.

Why the fix worked: Fresh profile — no cached mismatch. Windows negotiated from scratch.

If something seems off later: If problem recurs, issue is AP-side (check router channel, band,
security settings) or driver-related (update Wi-Fi driver). Client-side fixes can't resolve AP
configuration problems.
```

---

## DIAG-02 Targeted Collection

Per D-S4: defined here, invoked by SKILL.md post-routing silently. Soft-fail each command — if it fails or returns empty, set variable to "" and continue.

```powershell
# 1. Adapter state
$adapterState = powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Get-NetAdapter | Select-Object Name, InterfaceDescription, Status, MacAddress, LinkSpeed | ConvertTo-Json"
# 2. DNS config per interface
$dnsConfig = powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Get-DnsClientServerAddress | Where-Object {`$_.AddressFamily -eq 2 -or `$_.AddressFamily -eq 23} | Select-Object InterfaceAlias, ServerAddresses | ConvertTo-Json"
# 3. Full IP configuration
$ipConfig = powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Get-NetIPConfiguration | ConvertTo-Json"
# 4. Wi-Fi profiles (default case per D-N2 — always collect)
$wifiProfiles = netsh wlan show profiles
# Soft-fail all: on error or empty result, set variable = "" and continue
```

**Pre-capture for TCP/IP reset gate (run before presenting Gate 3 — not at DIAG-02 time):**

**Fix classification (TCP/IP reset):** Tier 2 — overwrites TCP/IP registry keys; reboot required; static IP configuration will be destroyed. Rollback pre-check via check-rollback.ps1 required.

**Rollback plan text (for TCP/IP reset gate):**
```
Rollback plan:
Network configuration captured to: $env:TEMP\tier1-netconfig-[timestamp].json
Contains all adapter IP addresses, gateways, DNS servers, and prefix lengths. Use as reference
to manually reconfigure after reboot.

System Restore point [mostRecentDate] is the broader safety net.

WARNING: If this machine uses a static IP address, you MUST note the static IP, subnet mask,
gateway, and DNS server addresses before proceeding. They will need to be manually reconfigured
after reboot — TCP/IP reset will destroy static IP configuration.
```

**Change diff text (for TCP/IP reset gate, D-06 format):**
```
What changes: The Windows TCP/IP stack registry keys will be overwritten with default values.
This resets all TCP/IP parameters including MTU values, route table adjustments, and any
manually configured network settings.

Exact paths/keys/services: TCP/IP registry keys under
HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters and
HKLM\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters

Time estimate: Under 1 minute (reset is instant; reboot takes additional time)

Restart required: YES — TCP/IP stack reset takes effect after reboot.

**WARNING: Static IP configurations will be reset to DHCP. If this machine uses a static IP
address, you will need to reconfigure it manually after reboot.**
Check $env:TEMP\tier1-netconfig-[timestamp].json for the values to restore.
```

**Fix commands (canonical — TCP/IP reset gate):**
```powershell
# Capture rollback artifact (MUST run before reset):
$ts = Get-Date -f yyyyMMdd-HHmmss
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Get-NetIPConfiguration | ConvertTo-Json | Out-File `"$env:TEMP\tier1-netconfig-$ts.json`""
netsh int ip reset resetlog.txt
```

**Post-verification check (after reboot):**
```powershell
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Test-NetConnection -ComputerName 8.8.8.8 -Port 80 -InformationLevel Quiet"
powershell.exe -ExecutionPolicy Bypass -NonInteractive -Command "Resolve-DnsName google.com -ErrorAction SilentlyContinue | Select-Object Name, IPAddress | ConvertTo-Json"
```
Success: Test-NetConnection returns True; Resolve-DnsName returns IP addresses.

---

*Phase 4 output. Consumed by SKILL.md and governs routing for the Network/Connectivity problem domain.*
*Do not add UX copy (approval gate text, escape hatch instructions) to this file — those belong in SKILL.md.*
