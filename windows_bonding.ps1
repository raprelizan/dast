[CmdletBinding()]
param(
    [ValidateSet('up','down','status')]
    [string]$Action = 'status',

    [string]$Wan1Alias = 'Ethernet',
    [string]$Wan2Alias = 'Ethernet 2',

    [string]$Wan1Gateway,
    [string]$Wan2Gateway,

    [int]$RouteMetric = 25
)

$ErrorActionPreference = 'Stop'

function Assert-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        throw 'Run PowerShell as Administrator.'
    }
}

function Get-IfIndexOrThrow([string]$alias) {
    $nic = Get-NetAdapter -Name $alias -ErrorAction SilentlyContinue
    if (-not $nic) { throw "Interface '$alias' not found." }
    if ($nic.Status -ne 'Up') { throw "Interface '$alias' is not Up." }
    return $nic.ifIndex
}

function Infer-Gateway([int]$ifIndex) {
    $route = Get-NetRoute -AddressFamily IPv4 |
        Where-Object { $_.ifIndex -eq $ifIndex -and $_.DestinationPrefix -eq '0.0.0.0/0' } |
        Sort-Object RouteMetric |
        Select-Object -First 1

    if ($route) { return $route.NextHop }
    return $null
}

function Ensure-Route([string]$dest, [string]$nextHop, [int]$ifIndex, [int]$metric) {
    $existing = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix $dest -ErrorAction SilentlyContinue |
        Where-Object { $_.ifIndex -eq $ifIndex -and $_.NextHop -eq $nextHop }

    if ($existing) {
        Set-NetRoute -DestinationPrefix $dest -InterfaceIndex $ifIndex -NextHop $nextHop -RouteMetric $metric -ErrorAction SilentlyContinue | Out-Null
        Write-Host "[=] Route exists: $dest via $nextHop ifIndex=$ifIndex"
    } else {
        New-NetRoute -AddressFamily IPv4 -DestinationPrefix $dest -InterfaceIndex $ifIndex -NextHop $nextHop -RouteMetric $metric | Out-Null
        Write-Host "[+] Added route: $dest via $nextHop ifIndex=$ifIndex"
    }
}

function Remove-RouteSafe([string]$dest, [string]$nextHop, [int]$ifIndex) {
    $routes = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix $dest -ErrorAction SilentlyContinue |
        Where-Object { $_.ifIndex -eq $ifIndex -and $_.NextHop -eq $nextHop }

    foreach ($r in $routes) {
        Remove-NetRoute -AddressFamily IPv4 -DestinationPrefix $dest -InterfaceIndex $ifIndex -NextHop $nextHop -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "[-] Removed route: $dest via $nextHop ifIndex=$ifIndex"
    }
}

function Show-Status([int]$if1, [int]$if2, [string]$gw1, [string]$gw2) {
    Write-Host "`n=== Current split routes ==="
    Get-NetRoute -AddressFamily IPv4 |
        Where-Object {
            ($_.DestinationPrefix -eq '0.0.0.0/1' -or $_.DestinationPrefix -eq '128.0.0.0/1') -and
            (($_.ifIndex -eq $if1 -and $_.NextHop -eq $gw1) -or ($_.ifIndex -eq $if2 -and $_.NextHop -eq $gw2))
        } |
        Sort-Object DestinationPrefix, ifIndex |
        Format-Table DestinationPrefix, ifIndex, NextHop, RouteMetric -AutoSize
}

Assert-Admin

$if1 = Get-IfIndexOrThrow -alias $Wan1Alias
$if2 = Get-IfIndexOrThrow -alias $Wan2Alias

if (-not $Wan1Gateway) { $Wan1Gateway = Infer-Gateway -ifIndex $if1 }
if (-not $Wan2Gateway) { $Wan2Gateway = Infer-Gateway -ifIndex $if2 }

if (-not $Wan1Gateway -or -not $Wan2Gateway) {
    throw 'Could not infer gateways. Provide -Wan1Gateway and -Wan2Gateway explicitly.'
}

switch ($Action) {
    'up' {
        Write-Host "[i] Applying split default routes on Windows..."
        Write-Host "[i] WAN1: $Wan1Alias (ifIndex=$if1) gw=$Wan1Gateway"
        Write-Host "[i] WAN2: $Wan2Alias (ifIndex=$if2) gw=$Wan2Gateway"

        # Remove full default routes on selected adapters to avoid ambiguity.
        Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Where-Object { $_.ifIndex -eq $if1 -or $_.ifIndex -eq $if2 } |
            ForEach-Object {
                Remove-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -InterfaceIndex $_.ifIndex -NextHop $_.NextHop -Confirm:$false -ErrorAction SilentlyContinue
                Write-Host "[-] Removed default route: 0.0.0.0/0 via $($_.NextHop) ifIndex=$($_.ifIndex)"
            }

        # Split internet destinations into two halves.
        Ensure-Route -dest '0.0.0.0/1'   -nextHop $Wan1Gateway -ifIndex $if1 -metric $RouteMetric
        Ensure-Route -dest '128.0.0.0/1' -nextHop $Wan2Gateway -ifIndex $if2 -metric $RouteMetric

        Show-Status -if1 $if1 -if2 $if2 -gw1 $Wan1Gateway -gw2 $Wan2Gateway
        Write-Host "[+] Done. This is destination-split load sharing on a single Windows host (not true packet bonding)."
    }

    'down' {
        Write-Host "[i] Removing split routes..."
        Remove-RouteSafe -dest '0.0.0.0/1'   -nextHop $Wan1Gateway -ifIndex $if1
        Remove-RouteSafe -dest '128.0.0.0/1' -nextHop $Wan2Gateway -ifIndex $if2

        # Restore standard defaults for both WANs.
        Ensure-Route -dest '0.0.0.0/0' -nextHop $Wan1Gateway -ifIndex $if1 -metric ($RouteMetric + 5)
        Ensure-Route -dest '0.0.0.0/0' -nextHop $Wan2Gateway -ifIndex $if2 -metric ($RouteMetric + 5)

        Show-Status -if1 $if1 -if2 $if2 -gw1 $Wan1Gateway -gw2 $Wan2Gateway
        Write-Host "[+] Reverted."
    }

    'status' {
        Write-Host "[i] WAN1: $Wan1Alias (ifIndex=$if1) gw=$Wan1Gateway"
        Write-Host "[i] WAN2: $Wan2Alias (ifIndex=$if2) gw=$Wan2Gateway"
        Show-Status -if1 $if1 -if2 $if2 -gw1 $Wan1Gateway -gw2 $Wan2Gateway
    }
}
