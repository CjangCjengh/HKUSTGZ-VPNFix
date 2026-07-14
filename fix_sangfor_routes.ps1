#Requires -RunAsAdministrator
<#
.SYNOPSIS
    清理 Sangfor 学校 VPN 推送的过量路由，只保留校园内网段走 VPN。
.DESCRIPTION
    学校 VPN 会推送覆盖几乎整个 IPv4 公网的路由表，导致外网流量被迫走学校 VPN 变慢。
    此脚本在连接学校 VPN 后运行，删除所有通往 Sangfor 网关的公网路由，
    仅保留 RFC1918 内网段（10/8、172.16/12、192.168/16）走学校 VPN。
    配合 Clash 系统代理使用：外网走 Clash，校园网走学校 VPN。
    不在本地写任何日志文件。
#>

$ErrorActionPreference = "Continue"

# 1. 找到 Sangfor VPN 网卡
$sangforAdapter = Get-NetAdapter | Where-Object {
    $_.InterfaceDescription -match "Sangfor" -or $_.Name -match "Sangfor"
}

if (-not $sangforAdapter) {
    Write-Host "未找到 Sangfor VPN 网卡，请先连接学校 VPN。" -ForegroundColor Red
    exit 1
}

$ifIndex = $sangforAdapter.InterfaceIndex
Write-Host "找到 Sangfor 网卡: $($sangforAdapter.Name) (ifIndex=$ifIndex)" -ForegroundColor Cyan

# 2. 获取 Sangfor 分配的内网 IP 和网关
$sangforIP = (Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
$allSangforRoutes = Get-NetRoute -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue

# 网关通常是出现次数最多的 NextHop（除了 On-link）
$sangforGateway = $allSangforRoutes |
    Where-Object { $_.NextHop -and $_.NextHop -ne "0.0.0.0" -and $_.DestinationPrefix -ne "0.0.0.0/0" } |
    Group-Object NextHop |
    Sort-Object Count -Descending |
    Select-Object -First 1 -ExpandProperty Name

if (-not $sangforGateway) {
    Write-Host "无法确定 Sangfor 网关，请确认 VPN 已连接。" -ForegroundColor Red
    exit 1
}

Write-Host "Sangfor 本地 IP: $sangforIP" -ForegroundColor Cyan
Write-Host "Sangfor 网关: $sangforGateway" -ForegroundColor Cyan

# 3. 定义需要保留走学校 VPN 的内网白名单
$whitelist = @(
    @{ Prefix = "10.0.0.0/8";      Keep = $true },
    @{ Prefix = "172.16.0.0/12";    Keep = $true },
    @{ Prefix = "192.168.0.0/16";   Keep = $true }
)

function Test-PrefixInWhitelist {
    param([string]$DestPrefix)
    foreach ($entry in $whitelist) {
        $base = $entry.Prefix.Split('/')[0]
        $destBase = $DestPrefix.Split('/')[0]
        if ($destBase -like "$base*" -or $DestPrefix -eq $entry.Prefix) {
            return $true
        }
    }
    return $false
}

# 4. 删除不在白名单里的 Sangfor 路由
$deleted = 0
$kept = 0
$routesViaGateway = Get-NetRoute -AddressFamily IPv4 | Where-Object {
    $_.NextHop -eq $sangforGateway -and
    $_.DestinationPrefix -ne "0.0.0.0/0" -and
    $_.DestinationPrefix -notmatch "^224\." -and
    $_.DestinationPrefix -notmatch "^255\."
}

Write-Host "`n开始清理，共找到 $($routesViaGateway.Count) 条通往 Sangfor 的路由..." -ForegroundColor Yellow

foreach ($route in $routesViaGateway) {
    $dest = $route.DestinationPrefix
    if (Test-PrefixInWhitelist -DestPrefix $dest) {
        Write-Host "  [保留] $dest" -ForegroundColor DarkGray
        $kept++
    } else {
        try {
            Remove-NetRoute -DestinationPrefix $dest -NextHop $sangforGateway -InterfaceIndex $route.ifIndex -Confirm:$false -ErrorAction Stop
            Write-Host "  [删除] $dest" -ForegroundColor DarkGreen
            $deleted++
        } catch {
            Write-Host "  [失败] $dest - $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# 5. 确保白名单路由存在且 metric 较低
foreach ($entry in $whitelist) {
    $exists = Get-NetRoute -DestinationPrefix $entry.Prefix -NextHop $sangforGateway -InterfaceIndex $ifIndex -ErrorAction SilentlyContinue
    if (-not $exists) {
        New-NetRoute -DestinationPrefix $entry.Prefix -NextHop $sangforGateway -InterfaceIndex $ifIndex -RouteMetric 1 -ErrorAction SilentlyContinue | Out-Null
        Write-Host "  [新增] $($entry.Prefix)" -ForegroundColor Green
    }
}

# 6. 打印结果
Write-Host "`n清理完成：保留 $kept 条，删除 $deleted 条。" -ForegroundColor Green
Write-Host "现在可以启动 Clash，外网应走 WLAN/Clash，校园网走学校 VPN。" -ForegroundColor Green
