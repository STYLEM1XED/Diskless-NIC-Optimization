# ============================================================
# DISKLESS NIC OPTIMIZATION
# For Intel / Realtek / Killer network cards
# Existing registry values ONLY.
# Missing values are NEVER created.
# Original registry values are backed up first.
# CREATED BY STYLEM1XED
# ============================================================

$ErrorActionPreference = "SilentlyContinue"

# ------------------------------------------------------------
# Administrator check
# ------------------------------------------------------------

$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)

if (-not $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    Write-Host ""
    Write-Host "ERROR: Run this script as Administrator." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}


# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------

$nicClass =
    "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002bE10318}"

$tcpClass =
    "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"

$backupDir = "C:\Backup"

New-Item -ItemType Directory -Path $backupDir -Force | Out-Null


# ------------------------------------------------------------
# Header
# ------------------------------------------------------------

Clear-Host

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "             DISKLESS NIC OPTIMIZATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Existing registry values ONLY will be modified." -ForegroundColor Yellow
Write-Host "Missing values will be skipped." -ForegroundColor Yellow
Write-Host ""


# ------------------------------------------------------------
# Registry backup
# ------------------------------------------------------------

$regExe = Join-Path $env:SystemRoot "System32\reg.exe"

$backupFile =
    Join-Path $backupDir "NIC-Class-Backup.reg"

Write-Host "Creating registry backup..." -ForegroundColor Cyan

& $regExe export `
    "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002bE10318}" `
    $backupFile `
    /y | Out-Null

if (Test-Path $backupFile) {
    Write-Host "[OK] Backup created:" -ForegroundColor Green
    Write-Host "     $backupFile"
}
else {
    Write-Host "[WARNING] Backup could not be created." -ForegroundColor Red
}

Write-Host ""


# ------------------------------------------------------------
# Function: change existing registry value
# ------------------------------------------------------------

function Set-ExistingRegistryValue {

    param(
        [string]$Path,
        [string]$Name,
        $Value
    )

    if (-not (Test-Path $Path)) {
        Write-Host "[SKIP] Key not found: $Name" -ForegroundColor DarkYellow
        return
    }

    $key = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue

    if ($null -eq $key) {
        Write-Host "[SKIP] Cannot read key: $Name" -ForegroundColor DarkYellow
        return
    }

    $property = $key.PSObject.Properties[$Name]

    if ($null -eq $property) {
        Write-Host "[SKIP] $Name (not present)" -ForegroundColor DarkYellow
        return
    }

    try {

        $currentValue = $property.Value

        # Preserve existing registry type.

        if ($currentValue -is [byte]) {
            $Value = [byte]$Value
        }
        elseif ($currentValue -is [int16]) {
            $Value = [int16]$Value
        }
        elseif ($currentValue -is [int32]) {
            $Value = [int32]$Value
        }
        elseif ($currentValue -is [int64]) {
            $Value = [int64]$Value
        }
        elseif ($currentValue -is [uint32]) {
            $Value = [uint32]$Value
        }
        elseif ($currentValue -is [string]) {
            $Value = [string]$Value
        }

        Set-ItemProperty `
            -Path $Path `
            -Name $Name `
            -Value $Value `
            -ErrorAction Stop

        Write-Host "[OK]   $Name = $Value" -ForegroundColor Green
    }
    catch {
        Write-Host "[FAIL] $Name : $($_.Exception.Message)" -ForegroundColor Red
    }
}


# ------------------------------------------------------------
# Find physical adapters
# ------------------------------------------------------------

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "NETWORK ADAPTERS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue

if (-not $adapters) {

    Write-Host "No physical network adapters found." -ForegroundColor Red

    Read-Host "Press Enter to exit"

    exit 1
}


# ------------------------------------------------------------
# Process adapters
# ------------------------------------------------------------

foreach ($adapter in $adapters) {

    $name = $adapter.Name
    $description = $adapter.InterfaceDescription
    $guid = $adapter.InterfaceGuid

    Write-Host ""
    Write-Host "------------------------------------------------------------"
    Write-Host "Adapter:     $name"
    Write-Host "Description: $description"
    Write-Host "GUID:        $guid"
    Write-Host "Status:      $($adapter.Status)"
    Write-Host "------------------------------------------------------------"


    # --------------------------------------------------------
    # Skip virtual adapters
    # --------------------------------------------------------

    if (
        $description -match
        "VMware|VirtualBox|Hyper-V|Virtual Ethernet|TAP|VPN|WSL|Loopback"
    ) {

        Write-Host "[SKIP] Virtual adapter." -ForegroundColor DarkYellow

        continue
    }


    # --------------------------------------------------------
    # Detect vendor
    # --------------------------------------------------------

    $vendor = "UNKNOWN"

    if ($description -match "Realtek") {
        $vendor = "REALTEK"
    }
    elseif ($description -match "Intel") {
        $vendor = "INTEL"
    }
    elseif ($description -match "Killer") {
        $vendor = "KILLER"
    }

    Write-Host "Vendor:      $vendor"


    if ($vendor -eq "UNKNOWN") {

        Write-Host "[SKIP] Unsupported NIC vendor." -ForegroundColor DarkYellow

        continue
    }


    # --------------------------------------------------------
    # Find corresponding registry key
    # --------------------------------------------------------

    $adapterKey = $null

    $subKeys = Get-ChildItem -Path $nicClass -ErrorAction SilentlyContinue

    foreach ($subKey in $subKeys) {

        $props = Get-ItemProperty `
            -Path $subKey.PSPath `
            -ErrorAction SilentlyContinue

        if ($null -eq $props) {
            continue
        }

        if (
            $props.NetCfgInstanceId `
            -and
            ($props.NetCfgInstanceId -eq $guid)
        ) {

            $adapterKey = $subKey.PSPath

            break
        }
    }


    if (-not $adapterKey) {

        Write-Host "[SKIP] Matching NIC registry key not found." `
            -ForegroundColor DarkYellow

        continue
    }


    Write-Host "Registry:    $adapterKey"
    Write-Host ""


    # ========================================================
    # COMMON SETTINGS
    # ========================================================

    Write-Host "[COMMON SETTINGS]" -ForegroundColor Cyan

    Set-ExistingRegistryValue `
        $adapterKey "*FlowControl" 0

    Set-ExistingRegistryValue `
        $adapterKey "FlowControl" 0

    Set-ExistingRegistryValue `
        $adapterKey "*GigaLite" 0

    Set-ExistingRegistryValue `
        $adapterKey "GigaLite" 0

    Set-ExistingRegistryValue `
        $adapterKey "*InterruptModeration" 0

    Set-ExistingRegistryValue `
        $adapterKey "InterruptModeration" 0


    # ========================================================
    # OFFLOADS
    # ========================================================

    Write-Host ""
    Write-Host "[OFFLOADS]" -ForegroundColor Cyan

    Set-ExistingRegistryValue `
        $adapterKey "*LsoV1IPv4" 0

    Set-ExistingRegistryValue `
        $adapterKey "LsoV2IPv4" 0

    Set-ExistingRegistryValue `
        $adapterKey "LsoV2IPv6" 0

    Set-ExistingRegistryValue `
        $adapterKey "*LsoV2IPv4" 0

    Set-ExistingRegistryValue `
        $adapterKey "*LsoV2IPv6" 0

    Set-ExistingRegistryValue `
        $adapterKey "*PMARPOffload" 0

    Set-ExistingRegistryValue `
        $adapterKey "*PMNSOffload" 0

    Set-ExistingRegistryValue `
        $adapterKey "*IPChecksumOffloadIPv4" 0

    Set-ExistingRegistryValue `
        $adapterKey "*IPChecksumOffloadIPv6" 0

    Set-ExistingRegistryValue `
        $adapterKey "*TCPChecksumOffloadIPv4" 0

    Set-ExistingRegistryValue `
        $adapterKey "*TCPChecksumOffloadIPv6" 0

    Set-ExistingRegistryValue `
        $adapterKey "*UDPChecksumOffloadIPv4" 0

    Set-ExistingRegistryValue `
        $adapterKey "*UDPChecksumOffloadIPv6" 0

    Set-ExistingRegistryValue `
        $adapterKey "*TCPUDPChecksumOffloadIPv4" 0

    Set-ExistingRegistryValue `
        $adapterKey "*TCPUDPChecksumOffloadIPv6" 0

    Set-ExistingRegistryValue `
        $adapterKey "TCPUDPChecksumOffloadIPv4" 0

    Set-ExistingRegistryValue `
        $adapterKey "TCPUDPChecksumOffloadIPv6" 0


    # ========================================================
    # POWER SAVING
    # ========================================================

    Write-Host ""
    Write-Host "[POWER SAWING]" -ForegroundColor Cyan

    Set-ExistingRegistryValue `
        $adapterKey "AdvancedEEE" 0

    Set-ExistingRegistryValue `
        $adapterKey "*AdvancedEEE" 0

    Set-ExistingRegistryValue `
        $adapterKey "EEE" 0

    Set-ExistingRegistryValue `
        $adapterKey "*EEE" 0

    Set-ExistingRegistryValue `
        $adapterKey "EnableGreenEthernet" 0

    Set-ExistingRegistryValue `
        $adapterKey "*GreenEthernet" 0

    Set-ExistingRegistryValue `
        $adapterKey "PowerSavingMode" 0

    Set-ExistingRegistryValue `
        $adapterKey "*PowerSavingMode" 0


    # ========================================================
    # WAKE ON LAN
    # ========================================================

    Write-Host ""
    Write-Host "[WAKE ON LAN]" -ForegroundColor Cyan

    Set-ExistingRegistryValue `
        $adapterKey "*WakeOnMagicPacket" 1

    Set-ExistingRegistryValue `
        $adapterKey "*WakeOnPattern" 1

    Set-ExistingRegistryValue `
        $adapterKey "S5WakeOnLan" 1

    Set-ExistingRegistryValue `
        $adapterKey "EnablePME" 1


    # ========================================================
    # VENDOR
    # ========================================================

    if ($vendor -eq "REALTEK") {

        Write-Host ""
        Write-Host "[REALTEK]" -ForegroundColor Cyan

        Set-ExistingRegistryValue `
            $adapterKey "EEE" 0

        Set-ExistingRegistryValue `
            $adapterKey "*EEE" 0

        Set-ExistingRegistryValue `
            $adapterKey "EnableGreenEthernet" 0

        Set-ExistingRegistryValue `
            $adapterKey "*GreenEthernet" 0
    }


    if ($vendor -eq "INTEL") {

        Write-Host ""
        Write-Host "[INTEL]" -ForegroundColor Cyan

        Set-ExistingRegistryValue `
            $adapterKey "EEE" 0

        Set-ExistingRegistryValue `
            $adapterKey "*EEE" 0
    }


    if ($vendor -eq "KILLER") {

        Write-Host ""
        Write-Host "[KILLER]" -ForegroundColor Cyan

        Set-ExistingRegistryValue `
            $adapterKey "EEE" 0

        Set-ExistingRegistryValue `
            $adapterKey "*EEE" 0
    }


    Write-Host ""
    Write-Host "[DONE] $name" -ForegroundColor Green
}


# ============================================================
# TCP SETTINGS
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "TCP PARAMETERS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

foreach ($adapter in $adapters) {

    $guid = $adapter.InterfaceGuid

    if (-not $guid) {
        continue
    }

    $tcpPath = Join-Path $tcpClass $guid

    Write-Host ""
    Write-Host "Interface: $guid"

    # Existing values only.
    Set-ExistingRegistryValue `
        $tcpPath "TcpAckFrequency" 1

    Set-ExistingRegistryValue `
        $tcpPath "TcpDelAckTicks" 0
}


# ============================================================
# COMPLETE
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "                 OPTIMIZATION COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

Write-Host "Backup:"
Write-Host $backupFile

Write-Host ""
Write-Host "Missing registry values were NOT created."
Write-Host ""
Write-Host "A reboot is recommended."
Write-Host ""

Read-Host "Press Enter to exit"
