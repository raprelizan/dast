[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Write-Host "=== Windows Multi-WAN Precheck ===" -ForegroundColor Cyan

$adapters = Get-NetAdapter |
    Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface -eq $true }

if (-not $adapters) {
    Write-Host "[!] لم يتم العثور على أي كرت شبكة فعال." -ForegroundColor Red
    exit 1
}

Write-Host "\n[+] Active adapters:" -ForegroundColor Green
$adapters | Select-Object Name, InterfaceDescription, ifIndex, LinkSpeed | Format-Table -AutoSize

$defaultRoutes = Get-NetRoute -AddressFamily IPv4 |
    Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' } |
    Sort-Object ifIndex, RouteMetric

Write-Host "\n[+] Default IPv4 routes:" -ForegroundColor Green
if ($defaultRoutes) {
    $defaultRoutes | Select-Object ifIndex, NextHop, RouteMetric, ifMetric | Format-Table -AutoSize
} else {
    Write-Host "[!] لا يوجد Default Route IPv4." -ForegroundColor Yellow
}

$wanIfIndexes = $defaultRoutes | Select-Object -ExpandProperty ifIndex -Unique
$wanAdapters = @()
if ($wanIfIndexes) {
    $wanAdapters = $adapters | Where-Object { $wanIfIndexes -contains $_.ifIndex }
}

Write-Host "\n[+] Detected WAN candidates (adapters with default route):" -ForegroundColor Green
if ($wanAdapters) {
    $wanAdapters | Select-Object Name, ifIndex, LinkSpeed | Format-Table -AutoSize
} else {
    Write-Host "[!] لم يتم اكتشاف WAN adapters." -ForegroundColor Yellow
}

if ($wanAdapters.Count -lt 2) {
    Write-Host "\n[!] النتيجة: لديك أقل من خطي إنترنت WAN فعالين." -ForegroundColor Yellow
    Write-Host "    لا يمكن تحقيق Multi-WAN/Bonding من جهازك الحالي بهذه الحالة." -ForegroundColor Yellow
    Write-Host "    الحل: تحتاج على الأقل 2 اتصالات إنترنت مستقلة (مثال: DSL1 + DSL2 أو DSL + 4G)." -ForegroundColor Yellow
    exit 2
}

Write-Host "\n[+] ممتاز: لديك $($wanAdapters.Count) واجهات WAN. يمكنك المتابعة بحل Multi-WAN عبر راوتر Linux/OpenWrt أو برنامج Bonding." -ForegroundColor Green
exit 0
