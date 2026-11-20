[CmdletBinding()]
param(
    [ValidateSet('Start','Network','Restore','Stop','Status','Setup','Dhcp')][string]$Action='Status',
    [string]$KitRoot='',
    [string]$ConfigPath='',
    [string]$InstallerRoot='',
    [string]$InstallerHashPath='',
    [switch]$DryRun,
    [switch]$NonInteractive,
    [switch]$StopPrograms
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if (-not $KitRoot) { $KitRoot=Split-Path -Parent $PSScriptRoot }
if (-not $ConfigPath) { $ConfigPath=Join-Path $PSScriptRoot 'settings.json' }
if (-not $InstallerHashPath) { $InstallerHashPath=Join-Path $PSScriptRoot 'installer-hashes.json' }
$KitRoot=[IO.Path]::GetFullPath($KitRoot)
$ConfigPath=[IO.Path]::GetFullPath($ConfigPath)
$InstallerHashPath=[IO.Path]::GetFullPath($InstallerHashPath)
if ($InstallerRoot) { $InstallerRoot=[IO.Path]::GetFullPath($InstallerRoot) }
. (Join-Path $PSScriptRoot 'RM26.Common.ps1')
$stateDir = Join-Path $env:LOCALAPPDATA 'SPR-RM26'
$statePath = Join-Path $stateDir 'network-before.json'
$requiresAdmin = $Action -in @('Network','Restore','Setup','Dhcp','Stop')

# Read-only preflight before UAC. An already prepared computer opens no installer
# or administrator prompt. Only explicit network setup needs a match.
try {
    if ($Action -eq 'Setup' -and -not $DryRun) {
        $dependencies=@(Get-RMDependencyStatus (Get-RMLayout $KitRoot))
        Show-RMDependencies $dependencies
        if (-not @($dependencies | Where-Object { -not $_.Installed }).Count) {
            Write-Host '依赖已齐全，全部跳过。直接点启动脚本即可。'
            exit 0
        }
    }
    if ($Action -eq 'Network') {
        $null=Get-RMPlan (Read-RMConfig $ConfigPath) -NonInteractive
    }
} catch { Write-Host "无法开始：$($_.Exception.Message)" -ForegroundColor Red; exit 1 }

# Relaunch this script, not a string of nested shell commands. Log and return actual exit status.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($requiresAdmin -and -not $DryRun -and -not $isAdmin) {
    $argv = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action {1} -KitRoot "{2}" -ConfigPath "{3}"' -f $PSCommandPath,$Action,$KitRoot,$ConfigPath
    if ($NonInteractive) { $argv += ' -NonInteractive' }
    if ($StopPrograms) { $argv += ' -StopPrograms' }
    if ($InstallerRoot) { $argv += ' -InstallerRoot "{0}"' -f $InstallerRoot }
    $argv += ' -InstallerHashPath "{0}"' -f $InstallerHashPath
    try {
        $p = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $argv -Verb RunAs -Wait -PassThru
        exit $p.ExitCode
    } catch { Write-Error '未获得管理员权限，没有修改网络。'; exit 1 }
}

$mutex = New-Object Threading.Mutex($false, 'Local\SPR-RM26-Tool')
$locked = $false
$transcribing = $false
try {
    $locked = $mutex.WaitOne(0)
    if (-not $locked) { throw 'Another RM26 operation is running; wait for it to finish.' }
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
        Start-Transcript -Path (Join-Path $stateDir ('operation-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')) | Out-Null
        $transcribing = $true
    }
    if ($Action -in @('Restore','Dhcp')) {
        # Recovery must NOT depend on the official software directory remaining intact.
        if ($DryRun) { Write-Host "[DRY RUN] $Action; backup=$statePath"; exit 0 }
        if ($Action -eq 'Restore') {
            if ($StopPrograms) {
                try { Stop-RMPrograms (Get-RMLayout $KitRoot) } catch { Write-Warning "停止程序未完成，但继续还原网络：$($_.Exception.Message)" }
            }
            Restore-RMState $statePath
        }
        else {
            $config = Read-RMConfig $ConfigPath
            $a = Select-RMAdapter $config.AdapterName $config.EngineAddress -NonInteractive:$NonInteractive -ExpectedSsid $config.ExpectedSsid
            # Explicit emergency action; normal Restore always restores the saved original config.
            Set-NetIPInterface -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -Dhcp Disabled
            Get-NetRoute -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false
            Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 | Remove-NetIPAddress -Confirm:$false
            Set-NetIPInterface -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -Dhcp Enabled -AutomaticMetric Enabled
            Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 | Set-DnsClientServerAddress -ResetServerAddresses
            & "$env:SystemRoot\System32\ipconfig.exe" /renew $a.Name | Out-Host
            if ($LASTEXITCODE -ne 0) { throw 'DHCP renew failed. Check the selected WiFi/LAN connection.' }
            Clear-DnsClientCache
        }
        exit 0
    }
    $layout = Get-RMLayout $KitRoot
    if ($Action -eq 'Status') {
        Write-Host "工具目录: $KitRoot"
        Get-RMAdapters | Format-Table ifIndex,Name,Status,InterfaceDescription -AutoSize | Out-Host
        Get-NetIPAddress -AddressFamily IPv4 | Format-Table InterfaceAlias,IPAddress,PrefixLength -AutoSize | Out-Host
        Show-RMDependencies @(Get-RMDependencyStatus $layout)
        foreach ($exe in @($layout.Engine,$layout.Client,$layout.Daemon)) { Write-Host "$([IO.Path]::GetFileName($exe)): $(@(Get-RMProcess $exe).Count) 个运行进程" }
        Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match '^USB\\VID_(2CA3|0000)' } | Select-Object Status,FriendlyName,InstanceId | Format-Table -Wrap | Out-Host
        Get-NetTCPConnection -LocalPort 3333 -ErrorAction SilentlyContinue | Format-Table LocalAddress,State,OwningProcess | Out-Host
        Write-Host "备份/操作日志: $stateDir"
        Write-Host 'USB 描述符失败表示枚举未完成；不能仅凭此断定线材、驱动或控制器损坏。'
        exit 0
    }
    if ($DryRun) {
        $layout | Format-List | Out-Host
        if ($Action -eq 'Setup') {
            $installers=$layout.Tools
            if ($InstallerRoot) { $installers=$InstallerRoot }
            Write-Host "[DRY RUN] Installers: $installers; hashes: $InstallerHashPath"
            Show-RMDependencies @(Get-RMDependencyStatus $layout)
        }
        if ($Action -eq 'Network') {
            $config = Read-RMConfig $ConfigPath
            Get-RMPlan $config -NonInteractive:$NonInteractive | ForEach-Object { Write-Host "[DRY RUN] $($_.Adapter.Name) -> $($_.Address)/$($_.Prefix), no gateway; backup first" }
        }
        Write-Host "[DRY RUN] $Action; no programs, installers or network changes executed."
        exit 0
    }
    switch ($Action) {
        'Setup' {
            $installers=$layout.Tools
            if ($InstallerRoot) { $installers=$InstallerRoot }
            Install-RMDependencies $layout $installers $InstallerHashPath
        }
        'Start' { Start-RMPrograms $layout }
        'Stop' { Stop-RMPrograms $layout }
        'Network' {
            $config = Read-RMConfig $ConfigPath
            $plan = @(Get-RMPlan $config -NonInteractive:$NonInteractive)
            $plan | ForEach-Object { Write-Host "将配置 $($_.Adapter.Name): $($_.Address)/24，不设默认网关。" }
            # Probe for address conflicts before changing anything. ICMP silence is not proof of no conflict.
            foreach ($p in $plan) {
                $own = @(Get-NetIPAddress -InterfaceIndex $p.Adapter.ifIndex -AddressFamily IPv4 | Where-Object IPAddress -EQ $p.Address)
                if (-not $own.Count -and (Test-Connection $p.Address -Count 1 -Quiet -ErrorAction SilentlyContinue)) { throw "Address already responds: $($p.Address). Do not assign the same IP to two computers." }
            }
            Enable-RMNetwork $plan $layout $statePath $config.ClientSubnet
            Write-Host '比赛网络已配置。可打开官方软件。收工时运行关闭并还原脚本。'
        }
    }
} catch { Write-Host "失败: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }
finally {
    if ($transcribing) { Stop-Transcript | Out-Null }
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
