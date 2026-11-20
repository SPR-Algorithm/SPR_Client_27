# Windows PowerShell 5.1+. This file is UTF-8 with BOM in the deployed kit.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-RMConfig([string]$Path) {
    $c = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($k in @('EngineAddress','AdapterName','ClientAdapterName','ClientHostAddress','ClientSubnet','ExpectedSsid')) {
        if (-not ($c.PSObject.Properties.Name -contains $k)) { throw "Configuration missing: $k" }
    }
    foreach ($address in @($c.EngineAddress, $c.ClientHostAddress)) {
        $ip = $null
        if (-not [Net.IPAddress]::TryParse($address, [ref]$ip) -or $ip.AddressFamily -ne 'InterNetwork') {
            throw "Invalid IPv4 address: $address"
        }
    }
    if ($c.ClientSubnet -notmatch '^\d+\.\d+\.\d+\.\d+/\d+$') { throw 'Invalid ClientSubnet CIDR' }
    return $c
}

function Find-RMProgram([string]$Directory, [string]$Name) {
    $matches = @(Get-ChildItem -LiteralPath $Directory -Filter $Name -File -Recurse -ErrorAction SilentlyContinue)
    if ($matches.Count -ne 1) { throw "Expected one $Name under $Directory; found $($matches.Count). Copy the COMPLETE official package." }
    return $matches[0].FullName
}

function Get-RMLayout([string]$Root) {
    # Discover by folder prefix so the directory can be renamed/localized or copied to another user/drive.
    $engineDir = @(Get-ChildItem -LiteralPath $Root -Directory | Where-Object Name -Like '01-*')
    $clientDir = @(Get-ChildItem -LiteralPath $Root -Directory | Where-Object Name -Like '02-*')
    if ($engineDir.Count -ne 1 -or $clientDir.Count -ne 1) { throw 'Kit must contain one 01-* engine and one 02-* client directory.' }
    $engine = Find-RMProgram $engineDir[0].FullName 'RoboMasterEngine.exe'
    $client = Find-RMProgram $clientDir[0].FullName 'RoboMasterClient.exe'
    $clientHome = Split-Path -Parent $client
    $toolsDir = Join-Path $clientHome 'RoboMasterClient_Data\StreamingAssets\Tools'
    $daemon = Join-Path $toolsDir 'RMClientDaemon\RMClientDaemon.exe'
    $start = Join-Path (Split-Path -Parent $clientHome) 'start.bat'
    foreach ($f in @($daemon,$start)) { if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "Missing official file: $f" } }
    return [pscustomobject]@{ Engine=$engine; Client=$client; Daemon=$daemon; Start=$start; Tools=$toolsDir }
}

function Get-RMAdapters {
    return @(Get-NetAdapter | Where-Object { $_.HardwareInterface -and $_.Status -eq 'Up' } | Sort-Object ifIndex)
}

function Get-RMNetworkProfiles {
    try { return @(Get-NetConnectionProfile -ErrorAction Stop) } catch { return @() }
}

function Select-RMAdapter([string]$Name, [string]$Address, [switch]$NonInteractive, [string]$ExpectedSsid='') {
    $adapters = @(Get-RMAdapters)
    if ($Name) {
        $chosen = @($adapters | Where-Object Name -EQ $Name)
        if ($chosen.Count -ne 1) { throw "Configured competition connection is not connected: $Name. Connect the competition cable/WiFi first." }
        return $chosen[0]
    }
    if ($ExpectedSsid) {
        $profiles = @(Get-RMNetworkProfiles | Where-Object Name -EQ $ExpectedSsid)
        $profileIndexes = @($profiles | ForEach-Object InterfaceIndex)
        $wifi = @($adapters | Where-Object { $profileIndexes -contains $_.ifIndex })
        if ($wifi.Count -eq 1) { return $wifi[0] }
    }
    $prefix = $Address.Substring(0, $Address.LastIndexOf('.') + 1)
    $candidates = @($adapters | Where-Object {
        $idx = $_.ifIndex
        @(Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object IPAddress -Like "$prefix*").Count -gt 0
    })
    if ($candidates.Count -eq 1) { return $candidates[0] }
    if ($candidates.Count -eq 0) {
        throw "没有检测到比赛局域网。请先把网线插好，或在 Windows 连上 $ExpectedSsid，再重新点启动。目标网段 $($prefix)0/24；未修改网络。"
    }
    throw "有多个连接都在比赛网段：$($candidates.Name -join '、')。请断开多余的比赛网络连接后重试；未修改网络。"
}

function Get-RMPlan($Config, [switch]$NonInteractive) {
    $engine = Select-RMAdapter $Config.AdapterName $Config.EngineAddress -NonInteractive:$NonInteractive -ExpectedSsid $Config.ExpectedSsid
    $plan = @([pscustomobject]@{ Adapter=$engine; Address=$Config.EngineAddress; Prefix=24 })
    if ($Config.ClientAdapterName) {
        $direct = Select-RMAdapter $Config.ClientAdapterName $Config.ClientHostAddress -NonInteractive:$NonInteractive
        if ($direct.InterfaceGuid -eq $engine.InterfaceGuid) { throw 'Engine and direct-client adapters must be different.' }
        $plan += [pscustomobject]@{ Adapter=$direct; Address=$Config.ClientHostAddress; Prefix=24 }
    }
    return $plan
}

function Get-RMAdapterSnapshot($Adapter) {
    $v4 = Get-NetIPInterface -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4
    $reg = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\' + $Adapter.InterfaceGuid
    $dnsRegistry = Get-ItemProperty -LiteralPath $reg -ErrorAction SilentlyContinue
    $manualDns = ''
    if ($dnsRegistry -and $dnsRegistry.PSObject.Properties['NameServer']) { $manualDns = [string]$dnsRegistry.NameServer }
    return [pscustomobject]@{
        Guid=[string]$Adapter.InterfaceGuid; Name=$Adapter.Name; Dhcp=[string]$v4.Dhcp
        AutomaticMetric=[string]$v4.AutomaticMetric; InterfaceMetric=$v4.InterfaceMetric
        Addresses=@(Get-NetIPAddress -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 | Where-Object PrefixOrigin -EQ Manual | Select-Object IPAddress,PrefixLength,SkipAsSource)
        Gateways=@(Get-NetRoute -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Select-Object NextHop,RouteMetric)
        ManualDns=[string]$manualDns
        Dns=@((Get-DnsClientServerAddress -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4).ServerAddresses)
    }
}

function Save-RMState([string]$Path, $State) {
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $State | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath ($Path + '.tmp') -Encoding UTF8
    Move-Item -LiteralPath ($Path + '.tmp') -Destination $Path -Force
}

function Renew-RMLease([string]$Name) {
    & "$env:SystemRoot\System32\ipconfig.exe" /renew $Name | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "DHCP renew failed on $Name. Backup retained; reconnect WiFi and retry." }
}

function Get-RMState([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $s = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($s.Computer -ne $env:COMPUTERNAME) { throw 'Backup belongs to another computer; refusing to apply it.' }
    return $s
}

function Set-RMStaticAddress($Adapter, [string]$Address, [int]$Prefix) {
    $index = $Adapter.ifIndex
    Set-NetIPInterface -InterfaceIndex $index -AddressFamily IPv4 -Dhcp Disabled -AutomaticMetric Disabled -InterfaceMetric 300
    Get-NetRoute -InterfaceIndex $index -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false
    Get-NetIPAddress -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -ne $Address } | Remove-NetIPAddress -Confirm:$false
    $existing = @(Get-NetIPAddress -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -eq $Address -and $_.PrefixLength -eq $Prefix })
    if ($existing.Count -eq 0) {
        Get-NetIPAddress -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false
        New-NetIPAddress -InterfaceIndex $index -IPAddress $Address -PrefixLength $Prefix | Out-Null
    }
    # No default gateway or forced DNS on the isolated competition network.
    Get-DnsClientServerAddress -InterfaceIndex $index -AddressFamily IPv4 | Set-DnsClientServerAddress -ResetServerAddresses
    $verified = @(Get-NetIPAddress -InterfaceIndex $index -AddressFamily IPv4 | Where-Object { $_.IPAddress -eq $Address -and $_.PrefixLength -eq $Prefix })
    if ($verified.Count -ne 1) { throw "Static IP verification failed: $Address" }
}

function Restore-RMState([string]$Path) {
    $s = Get-RMState $Path
    if (-not $s -or $s.Restored) { Write-Host '没有待还原的网络备份。'; return }
    foreach ($saved in $s.Adapters) {
        $a = @(Get-NetAdapter | Where-Object { [string]$_.InterfaceGuid -eq $saved.Guid })
        if ($a.Count -ne 1) { throw "Original adapter missing: $($saved.Name). Reconnect it and run Restore again." }
        $i = $a[0].ifIndex
        Set-NetIPInterface -InterfaceIndex $i -AddressFamily IPv4 -Dhcp Disabled
        Get-NetRoute -InterfaceIndex $i -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false
        Get-NetIPAddress -InterfaceIndex $i -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false
        if ($saved.Dhcp -eq 'Enabled') {
            Set-NetIPInterface -InterfaceIndex $i -AddressFamily IPv4 -Dhcp Enabled
        } else {
            foreach ($addr in $saved.Addresses) {
                New-NetIPAddress -InterfaceIndex $i -IPAddress $addr.IPAddress -PrefixLength $addr.PrefixLength -SkipAsSource $addr.SkipAsSource | Out-Null
            }
            foreach ($gateway in $saved.Gateways) {
                New-NetRoute -InterfaceIndex $i -DestinationPrefix '0.0.0.0/0' -NextHop $gateway.NextHop -RouteMetric $gateway.RouteMetric | Out-Null
            }
        }
        if ($saved.ManualDns) { Get-DnsClientServerAddress -InterfaceIndex $i -AddressFamily IPv4 | Set-DnsClientServerAddress -ServerAddresses @($saved.Dns) }
        else { Get-DnsClientServerAddress -InterfaceIndex $i -AddressFamily IPv4 | Set-DnsClientServerAddress -ResetServerAddresses }
        if ($saved.AutomaticMetric -eq 'Enabled') { Set-NetIPInterface -InterfaceIndex $i -AddressFamily IPv4 -AutomaticMetric Enabled }
        else { Set-NetIPInterface -InterfaceIndex $i -AddressFamily IPv4 -AutomaticMetric Disabled -InterfaceMetric $saved.InterfaceMetric }
        if ($saved.Dhcp -eq 'Enabled') {
            # Renew only the selected adapter, never release all adapters.
            Renew-RMLease $a[0].Name
        }
    }
    foreach ($rule in $s.FirewallRules) { Remove-NetFirewallRule -Name $rule -ErrorAction SilentlyContinue }
    Clear-DnsClientCache
    $s.Restored = $true
    Save-RMState $Path $s
    Write-Host '已恢复所选网卡原来的 IP、DNS、网关和跃点数，并移除本次放行规则。'
}

function Enable-RMNetwork($Plan, $Layout, [string]$StatePath, [string]$ClientSubnet) {
    $saved = Get-RMState $StatePath
    if ($saved -and -not $saved.Restored) {
        $guids = @($saved.Adapters | ForEach-Object Guid)
        if (@($Plan | Where-Object { $guids -notcontains [string]$_.Adapter.InterfaceGuid }).Count -gt 0) {
            throw 'Another network session is active. Restore first; original backup was NOT overwritten.'
        }
        Write-Host '复用本次启动前的原始备份（不会覆盖）。'
    } else {
        $saved = [pscustomobject]@{
            Computer=$env:COMPUTERNAME; Created=(Get-Date).ToString('o'); Restored=$false
            Adapters=@($Plan | ForEach-Object { Get-RMAdapterSnapshot $_.Adapter })
            FirewallRules=@(); Processes=@()
        }
    }
    # Persist BEFORE changes, including rule names in case creation fails midway.
    $session = [guid]::NewGuid().ToString('N')
    $ruleNames = @("RM26-$session-Engine", "RM26-$session-Client")
    $saved.FirewallRules = @($saved.FirewallRules) + $ruleNames
    Save-RMState $StatePath $saved
    try {
        foreach ($p in $Plan) { Set-RMStaticAddress $p.Adapter $p.Address $p.Prefix }
        $aliases = @($Plan | ForEach-Object { $_.Adapter.Name })
        # Application-only inbound access on selected interfaces and private LAN ranges.
        # Video 3334 is received on Linux, not here. Never disable the Windows firewall.
        $ranges = @($ClientSubnet) + @($Plan | ForEach-Object { $_.Address.Substring(0, $_.Address.LastIndexOf('.') + 1) + '0/24' })
        $ranges = @($ranges | Select-Object -Unique)
        New-NetFirewallRule -Name $ruleNames[0] -DisplayName 'RM26 engine (temporary)' -Direction Inbound -Action Allow -Program $Layout.Engine -InterfaceAlias $aliases -RemoteAddress $ranges -Profile Any | Out-Null
        New-NetFirewallRule -Name $ruleNames[1] -DisplayName 'RM26 player (temporary)' -Direction Inbound -Action Allow -Program $Layout.Client -InterfaceAlias $aliases -RemoteAddress $ranges -Profile Any | Out-Null
    } catch {
        $failure = $_
        try { Restore-RMState $StatePath } catch { Write-Warning "自动回滚失败，请运行 3-一键还原；备份保留在 $StatePath。$($_.Exception.Message)" }
        throw $failure
    }
}

function Get-RMProcess([string]$Exe) {
    $name = [IO.Path]::GetFileName($Exe)
    return @(Get-CimInstance Win32_Process -Filter "Name='$name'" | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.Equals($Exe, [StringComparison]::OrdinalIgnoreCase) })
}

function Get-RMDotNetRuntimes {
    $dotnet = Join-Path $env:ProgramFiles 'dotnet\dotnet.exe'
    if (-not (Test-Path -LiteralPath $dotnet)) { return @() }
    $runtimes = @(& $dotnet --list-runtimes)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot query x64 .NET runtime; use Diagnose to check the existing installation.' }
    return $runtimes
}

function Get-RMDotNetRequirements($Layout) {
    $requirements = @()
    $configs = @(Get-ChildItem -LiteralPath (Split-Path $Layout.Daemon -Parent) -Filter '*.runtimeconfig.json')
    if (-not $configs.Count) { throw 'Missing official runtimeconfig.json; copy the complete official player package.' }
    foreach ($file in $configs) {
        $r = (Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json).runtimeOptions
        $frameworks = @()
        if ($r.PSObject.Properties.Name -contains 'framework') { $frameworks += $r.framework }
        if ($r.PSObject.Properties.Name -contains 'frameworks') { $frameworks += $r.frameworks }
        $requirements += $frameworks
    }
    return $requirements
}

function Test-RMDotNetInstalled($Requirements, $Runtimes) {
    foreach ($f in $Requirements) {
        $required = [version]$f.version
        $pattern = '^' + [regex]::Escape($f.name) + '\s+(\d+\.\d+\.\d+)\s'
        $matchesRequirement = @($Runtimes | Where-Object {
            if ($_ -match $pattern) {
                $installed=[version]$Matches[1]
                $installed.Major -eq $required.Major -and $installed.Minor -eq $required.Minor -and $installed -ge $required
            }
        })
        if (-not $matchesRequirement.Count) { return $false }
    }
    return $true
}

function Get-RMVcRuntime {
    return Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64' -ErrorAction SilentlyContinue
}

function Get-RMRuntimeStatus($Layout) {
    $requirements = @(Get-RMDotNetRequirements $Layout)
    $dotnetReady = Test-RMDotNetInstalled $requirements @(Get-RMDotNetRuntimes)
    $minimum = [version]'14.26.28720.3' # Version of the official bundled VC++ installer.
    $vc = Get-RMVcRuntime
    $vcReady = $false
    if ($vc -and $vc.PSObject.Properties['Installed'] -and $vc.Installed -eq 1 -and $vc.PSObject.Properties['Version']) {
        $installed = $null
        if ([version]::TryParse(([string]$vc.Version).TrimStart('v','V'),[ref]$installed)) { $vcReady=$installed -ge $minimum }
    }
    return @(
        [pscustomobject]@{Key='DotNet';Name='.NET 7 x64 运行时';Installed=$dotnetReady;Installer='dotnet-runtime-7.0.4-win-x64.exe'},
        [pscustomobject]@{Key='VC';Name='Visual C++ x64 运行库';Installed=$vcReady;Installer='VC2015~2019_redist.x64.exe'}
    )
}

function Test-RMDJIDriverInstalled([string]$InfDirectory=(Join-Path $env:windir 'INF')) {
    # Published OEM INFs exist even when the receiver is unplugged. An uninstall
    # registry entry alone does not prove that the driver was actually installed.
    $video0=$false; $video1=$false; $serial=$false
    foreach ($file in Get-ChildItem -LiteralPath $InfDirectory -Filter 'oem*.inf' -File -ErrorAction Stop) {
        $content = [IO.File]::ReadAllText($file.FullName)
        if ($content -match '(?im)^\s*Provider\s*=.*' -and $content -match '(?i)libusb0') {
            # The official libusb INF defines VID/PID through [Strings] macros,
            # rather than spelling the full USB\... ID in its device list.
            if ($content -match '(?i)VID_2CA3&PID_1020&MI_00') { $video0=$true }
            if ($content -match '(?i)VID_2CA3&PID_1020&MI_01') { $video1=$true }
        }
        if ($content -match '(?i)USB\\VID_2CA3&PID_1020&MI_02' -and $content -match '(?i)usbser') { $serial=$true }
        if ($video0 -and $video1 -and $serial) { return $true }
    }
    return $false
}

function Get-RMDependencyStatus($Layout) {
    return @(Get-RMRuntimeStatus $Layout) + @(
        [pscustomobject]@{Key='DJI';Name='DJI 图传 USB 驱动';Installed=(Test-RMDJIDriverInstalled);Installer='DJI_Driver_Installer_32bit&64bit_4.8.11.exe'}
    )
}

function Show-RMDependencies($Dependencies) {
    foreach ($d in $Dependencies) {
        if ($d.Installed) { Write-Host "[已安装，跳过] $($d.Name)" }
        else { Write-Host "[缺少，待安装] $($d.Name)" }
    }
}

function Install-RMDependencies($Layout, [string]$InstallerRoot, [string]$HashFile) {
    $dependencies=@(Get-RMDependencyStatus $Layout)
    Show-RMDependencies $dependencies
    $reboot=$false
    foreach ($d in $dependencies) {
        if ($d.Installed) { continue }
        $installer=Join-Path $InstallerRoot $d.Installer
        if (-not (Test-Path -LiteralPath $installer)) { throw "Missing installer: $installer" }
        Test-RMInstaller $installer $HashFile
        Write-Host "正在补装：$($d.Name)"
        $process=Start-Process -FilePath $installer -Wait -PassThru
        if ($process.ExitCode -notin @(0,1638,3010)) { throw "Installer exit code $($process.ExitCode): $($d.Name)" }
        $current=@(Get-RMDependencyStatus $Layout | Where-Object Key -EQ $d.Key)[0]
        if ($process.ExitCode -eq 3010) {
            $reboot=$true
            Write-Warning "$($d.Name) 安装器要求重启；请保存工作后重启。"
        } elseif (-not $current.Installed) {
            throw "$($d.Name) 安装结束后仍未检测到。请检查安装器结果；脚本不会反复重装。"
        }
    }
    if ($reboot) { Write-Host '缺少的依赖安装已执行；请按安装器要求重启，再运行启动脚本。' }
    else { Write-Host '依赖已齐全。以后正常使用直接点启动脚本。' }
}

function Test-RMRuntime($Layout) {
    $missing=@(Get-RMRuntimeStatus $Layout | Where-Object { -not $_.Installed })
    if ($missing.Count) { throw "缺少运行依赖：$($missing.Name -join '、')。请先运行首次依赖安装脚本，只会补装缺项。" }
}

function Test-RMInstaller([string]$Installer, [string]$HashFile) {
    $signature = (Get-AuthenticodeSignature -FilePath $Installer).Status
    if ($signature -eq 'Valid') { return }
    $hashes = Get-Content -LiteralPath $HashFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $expected = $hashes.PSObject.Properties[[IO.Path]::GetFileName($Installer)]
    if ($signature -ne 'NotSigned' -or -not $expected -or (Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash -ne $expected.Value) {
        throw "Installer signature/hash verification failed: $Installer"
    }
    Write-Warning '官方 DJI 4.8.11 安装器外壳未签名；已核对固定文件 SHA-256。将打开官方安装界面，不关闭系统驱动签名校验。'
}

function Start-RMPrograms($Layout) {
    Test-RMRuntime $Layout
    if (@(Get-RMProcess $Layout.Engine).Count -eq 0) {
        Start-Process -FilePath $Layout.Engine -WorkingDirectory (Split-Path $Layout.Engine -Parent) | Out-Null
    }
    $clientLive = @(Get-RMProcess $Layout.Client).Count -gt 0
    $daemonLive = @(Get-RMProcess $Layout.Daemon).Count -gt 0
    if ($clientLive -and -not $daemonLive) {
        throw 'Player is running without its daemon. Close the player, then run Start again (do not double-click its EXE).'
    }
    if (-not $clientLive) {
        # Official batch stops matching old helpers. Do not interfere with a different kit.
        $others = @(Get-CimInstance Win32_Process | Where-Object {
            $_.Name -match '^(RoboMasterClient|RMClientDaemon|RMClientAssist_.*)\.exe$' -and
            $_.ExecutablePath -and -not $_.ExecutablePath.StartsWith((Split-Path $Layout.Start -Parent) + '\', [StringComparison]::OrdinalIgnoreCase)
        })
        if ($others.Count) { throw 'Another official player kit is running. Close it before starting this copy.' }
        Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList ('/d /c ""{0}""' -f $Layout.Start) -WorkingDirectory (Split-Path $Layout.Start -Parent) -WindowStyle Hidden | Out-Null
    }
    $limit = (Get-Date).AddSeconds(25)
    do {
        if (@(Get-RMProcess $Layout.Client).Count -and @(Get-RMProcess $Layout.Daemon).Count) { break }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $limit)
    if (-not @(Get-RMProcess $Layout.Client).Count -or -not @(Get-RMProcess $Layout.Daemon).Count) {
        throw 'Player/daemon failed to start. Run the diagnosis script and inspect the official Player.log.'
    }
    Write-Host '引擎、官方选手端、Daemon 已运行。请在引擎登录 DJI 账号，选手端按 P 登录本场机器人。'
}

function Stop-RMPrograms($Layout) {
    $roots = @((Split-Path $Layout.Engine -Parent), (Split-Path $Layout.Start -Parent))
    $processes = @(Get-CimInstance Win32_Process | Where-Object {
        $p = $_.ExecutablePath
        $p -and @($roots | Where-Object { $p.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
    })
    foreach ($p in $processes) { Stop-Process -Id $p.ProcessId -ErrorAction SilentlyContinue }
    Write-Host '已停止本工具目录内的官方程序和辅助进程。'
}
