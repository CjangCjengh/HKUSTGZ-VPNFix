#Requires -RunAsAdministrator
<#
.SYNOPSIS
    注册计划任务：Sangfor VPN 网卡连接后自动清理路由。
.DESCRIPTION
    注册完成后，任务会把清理逻辑以 Base64 编码内联到 powershell.exe 参数里，
    因此注册脚本本身和清理脚本本身都可以删除，不影响任务运行。
    任务不写入任何本地日志文件。
#>

$taskName = "CleanSangforRoutesOnConnect"
$taskDescription = "检测到 Sangfor VPN 连接后，自动清理过量公网路由"

# 内联清理脚本（不依赖外部 .ps1 文件）
# VPN 连接后 Sangfor 会分批推路由，所以循环清理：每 10 秒一次，最多 12 次（2 分钟），VPN 断开则提前退出
$cleanScript = @'
$ErrorActionPreference = "Continue"
$whitelist = @("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
function Test-PrefixInWhitelist($DestPrefix) {
    foreach ($p in $whitelist) {
        $base = $p.Split('/')[0]
        $destBase = $DestPrefix.Split('/')[0]
        if ($destBase -like "$base*" -or $DestPrefix -eq $p) { return $true }
    }
    return $false
}
function Get-SangforGateway() {
    $adapter = Get-NetAdapter | Where-Object { $_.InterfaceDescription -match "Sangfor" -or $_.Name -match "Sangfor" }
    if (-not $adapter -or $adapter.Status -ne "Up") { return $null }
    $routes = Get-NetRoute -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.NextHop -and $_.NextHop -ne "0.0.0.0" -and $_.DestinationPrefix -ne "0.0.0.0/0" }
    return $routes | Group-Object NextHop | Sort-Object Count -Descending | Select-Object -First 1 -ExpandProperty Name
}
$iter = 0
$maxIter = 12
while ($iter -lt $maxIter) {
    $gateway = Get-SangforGateway
    if (-not $gateway) { break }
    $routesViaGateway = Get-NetRoute -AddressFamily IPv4 | Where-Object {
        $_.NextHop -eq $gateway -and
        $_.DestinationPrefix -ne "0.0.0.0/0" -and
        $_.DestinationPrefix -notmatch "^224\." -and
        $_.DestinationPrefix -notmatch "^255\."
    }
    foreach ($route in $routesViaGateway) {
        $dest = $route.DestinationPrefix
        if (-not (Test-PrefixInWhitelist $dest)) {
            Remove-NetRoute -DestinationPrefix $dest -NextHop $gateway -InterfaceIndex $route.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
    foreach ($p in $whitelist) {
        $adapter = Get-NetAdapter | Where-Object { $_.InterfaceDescription -match "Sangfor" -or $_.Name -match "Sangfor" } | Select-Object -First 1
        if (-not $adapter) { continue }
        $exists = Get-NetRoute -DestinationPrefix $p -NextHop $gateway -InterfaceIndex $adapter.InterfaceIndex -ErrorAction SilentlyContinue
        if (-not $exists) {
            New-NetRoute -DestinationPrefix $p -NextHop $gateway -InterfaceIndex $adapter.InterfaceIndex -RouteMetric 1 -ErrorAction SilentlyContinue | Out-Null
        }
    }
    Start-Sleep -Seconds 10
    $iter++
}
'@

# 编码为 Base64（Unicode）内联执行
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cleanScript))
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"

# 事件触发器：NetworkProfile/Operational Event ID 10000，且适配器描述为 Sangfor
$xpath = @"
<QueryList>
  <Query Id="0" Path="Microsoft-Windows-NetworkProfile/Operational">
    <Select Path="Microsoft-Windows-NetworkProfile/Operational">
      *[System[(EventID=10000)]]
      [EventData[(Data[@Name='Description']='Sangfor SSL VPN CS Support System VNIC')]]
    </Select>
  </Query>
</QueryList>
"@

$trigger = Get-CimClass MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler |
    New-CimInstance -ClientOnly -Property @{
        Enabled = $true
        Subscription = $xpath
    }

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable

$task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description $taskDescription

# 如果任务已存在则先删除
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null

Write-Host "计划任务 '$taskName' 已注册。" -ForegroundColor Green
Write-Host "触发条件: Sangfor VPN 网卡连接 (NetworkProfile Event ID 10000)" -ForegroundColor Cyan
Write-Host "执行方式: powershell.exe -EncodedCommand（内联脚本，不依赖外部 .ps1）" -ForegroundColor Cyan
Write-Host "现在可以删除这两个 .ps1 文件，任务会继续正常工作。" -ForegroundColor Green
