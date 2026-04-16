[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Write-Host "=== Windows Multi-WAN Precheck ===" -ForegroundColor Cyan

$adapters = Get-NetAdapter |
    Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface -eq $true }

if (-not $adapters) {
    Write-Host "[!] No active hardware network adapters were found." -ForegroundColor Red
    exit 1
}

Write-Host "`n[+] Active adapters:" -ForegroundColor Green
$adapters | Select-Object Name, InterfaceDescription, ifIndex, LinkSpeed | Format-Table -AutoSize

$defaultRoutes = Get-NetRoute -AddressFamily IPv4 |
    Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' } |
    Sort-Object ifIndex, RouteMetric

Write-Host "`n[+] Default IPv4 routes:" -ForegroundColor Green
if ($defaultRoutes) {
    $defaultRoutes | Select-Object ifIndex, NextHop, RouteMetric, ifMetric | Format-Table -AutoSize
} else {
    Write-Host "[!] No IPv4 default route found." -ForegroundColor Yellow
}

$wanIfIndexes = @($defaultRoutes | Select-Object -ExpandProperty ifIndex -Unique)
$wanAdapters = @()
if ($wanIfIndexes.Count -gt 0) {
    $wanAdapters = @($adapters | Where-Object { $wanIfIndexes -contains $_.ifIndex })
}

Write-Host "`n[+] Detected WAN candidates (adapters with default route):" -ForegroundColor Green
if ($wanAdapters.Count -gt 0) {
    $wanAdapters | Select-Object Name, ifIndex, LinkSpeed | Format-Table -AutoSize
} else {
    Write-Host "[!] No WAN adapter candidates detected." -ForegroundColor Yellow
}

if ($wanAdapters.Count -lt 2) {
    Write-Host "`n[!] Result: fewer than two active WAN links were detected." -ForegroundColor Yellow
    Write-Host "    Multi-WAN/Bonding cannot work in this current setup." -ForegroundColor Yellow
    Write-Host "    You need at least two independent internet links (e.g., DSL1 + DSL2, or DSL + 4G)." -ForegroundColor Yellow
    exit 2
}

Write-Host "`n[+] Great: $($wanAdapters.Count) WAN adapters detected. You can continue with a Linux/OpenWrt Multi-WAN setup." -ForegroundColor Green
exit 0
