# No administrator privileges, Pester or real network mutations required.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts\portable\windows\RM26.Common.ps1')
# Keep the official Unity fixture paths below the Windows PowerShell 5.1 path limit.
$scratch=Join-Path $repo ('tmp\pw-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$script:passed=0
function Assert-RM($Condition,[string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:passed++
    Write-Output "PASS: $Message"
}
function Assert-RMThrows([scriptblock]$Run,[string]$Message) {
    $failed=$false
    try { & $Run | Out-Null } catch { $failed=$true }
    Assert-RM $failed $Message
}

# All network/process mutators below are mocked. Never call real networking from this test.
$script:calls=New-Object 'System.Collections.Generic.List[string]'
function Get-NetAdapter { return @(
    [pscustomobject]@{Name='Competition Ethernet';InterfaceGuid='test-a';ifIndex=8;HardwareInterface=$true;Status='Up'},
    [pscustomobject]@{Name='Phone uplink';InterfaceGuid='test-b';ifIndex=9;HardwareInterface=$true;Status='Up'}
) }
function Get-NetIPAddress { param($InterfaceIndex,$AddressFamily,$ErrorAction)
    if ($InterfaceIndex -eq 9) { return [pscustomobject]@{IPAddress=$script:phoneIp;PrefixLength=24;PrefixOrigin='Dhcp';SkipAsSource=$false} }
    if ($InterfaceIndex -eq 8 -and $script:competitionIp -ne '192.0.2.100') { return [pscustomobject]@{IPAddress=$script:competitionIp;PrefixLength=24;PrefixOrigin='Dhcp';SkipAsSource=$false} }
    return [pscustomobject]@{IPAddress='192.0.2.100';PrefixLength=24;PrefixOrigin='Dhcp';SkipAsSource=$false}
}
$script:phoneIp='198.51.100.2'; $script:competitionIp='192.0.2.100'; $script:profiles=@()
function Get-RMNetworkProfiles { return $script:profiles }
function Read-Host { throw 'Adapter input must never be requested' }
function Get-NetIPInterface { param($InterfaceIndex,$AddressFamily)
    return [pscustomobject]@{Dhcp='Enabled';AutomaticMetric='Enabled';InterfaceMetric=50}
}
function Get-ItemProperty { param($LiteralPath,$ErrorAction) return [pscustomobject]@{} }
function Get-NetRoute { param($InterfaceIndex,$AddressFamily,$DestinationPrefix,$ErrorAction) return @() }
function Get-DnsClientServerAddress { param($InterfaceIndex,$AddressFamily) return [pscustomobject]@{ServerAddresses=@('1.1.1.1')} }
function Set-RMStaticAddress { param($Adapter,$Address,$Prefix) $script:calls.Add("static:$($Adapter.Name)") }
function Set-NetIPInterface { param($InterfaceIndex,$AddressFamily,$Dhcp,$AutomaticMetric,$InterfaceMetric) $script:calls.Add("ipif:$Dhcp") }
function Remove-NetRoute { [CmdletBinding()]param([Parameter(ValueFromPipeline)]$InputObject,[switch]$Confirm) process {} }
function Remove-NetIPAddress { [CmdletBinding()]param([Parameter(ValueFromPipeline)]$InputObject,[switch]$Confirm) process { $script:calls.Add('remove-ip') } }
function New-NetIPAddress { param($InterfaceIndex,$IPAddress,$PrefixLength,$SkipAsSource) $script:calls.Add("restore-ip:$IPAddress/$PrefixLength") }
function New-NetRoute { param($InterfaceIndex,$DestinationPrefix,$NextHop,$RouteMetric) $script:calls.Add("gateway:$NextHop") }
function Set-DnsClientServerAddress {
    [CmdletBinding()]param([Parameter(ValueFromPipeline)]$InputObject,$InterfaceIndex,$ServerAddresses,[switch]$ResetServerAddresses)
    process { $script:calls.Add("dns:$($ServerAddresses -join ',')") }
}
function Remove-NetFirewallRule { param($Name,$ErrorAction) $script:calls.Add("remove-rule:$Name") }
function Clear-DnsClientCache { $script:calls.Add('flush') }
function Renew-RMLease { param($Name) $script:calls.Add("renew:$Name") }
function New-NetFirewallRule { param($Name,$DisplayName,$Direction,$Action,$Program,$InterfaceAlias,$RemoteAddress,$Profile)
    $script:calls.Add("add-rule:$Name")
    if ($script:failRule) { throw 'Injected firewall failure' }
}
$script:failRule=$false

try {
    # Parse every script with the same parser used by PowerShell, not text matching.
    foreach ($file in Get-ChildItem (Join-Path $repo 'scripts\portable') -Recurse -Filter '*.ps1') {
        $errors=$null; $tokens=$null
        $null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
        Assert-RM ($errors.Count -eq 0) "PowerShell syntax $($file.Name)"
    }
    $kit=Join-Path $scratch '别人的电脑 空格路径'
    $files=@('01-引擎\any-version\RoboMasterEngine.exe',
        '02-选手端\different-version\start.bat',
        '02-选手端\different-version\RoboMasterClient\RoboMasterClient.exe',
        '02-选手端\different-version\RoboMasterClient\RoboMasterClient_Data\StreamingAssets\Tools\RMClientDaemon\RMClientDaemon.exe')
    foreach ($relative in $files) {
        $file=Join-Path $kit $relative
        New-Item -ItemType Directory -Path (Split-Path $file -Parent) -Force | Out-Null
        Set-Content -LiteralPath $file -Value 'fixture'
    }
    $layout=Get-RMLayout $kit
    Set-Content -LiteralPath (Join-Path (Split-Path $layout.Daemon -Parent) 'RMClientDaemon.runtimeconfig.json') -Value '{"runtimeOptions":{"framework":{"name":"Microsoft.NETCore.App","version":"7.0.0"}}}' -Encoding UTF8
    Assert-RM ($layout.Engine.StartsWith($kit)) 'program discovery uses copied kit path'
    Assert-RM ($layout.Start.EndsWith('different-version\start.bat')) 'official batch entry, no version hard-code'
    $config=Read-RMConfig (Join-Path $repo 'scripts\portable\windows\settings.json')
    $config.AdapterName='Competition Ethernet'
    $plan=@(Get-RMPlan $config -NonInteractive)
    Assert-RM ($plan.Count -eq 1 -and $plan[0].Adapter.ifIndex -eq 8) 'explicit adapter, no WLAN assumption'
    $config.AdapterName=''
    Assert-RM ((Get-RMPlan $config)[0].Adapter.ifIndex -eq 8) 'connected competition LAN auto-selected without asking, phone uplink ignored'
    $script:competitionIp='203.0.113.116'
    Assert-RMThrows { Get-RMPlan $config } 'campus WiFi alone is rejected without guessing an adapter'
    $script:competitionIp='0.0.0.0'
    $script:profiles=@([pscustomobject]@{Name='robomaster-spr';InterfaceIndex=8})
    Assert-RM ((Get-RMPlan $config)[0].Adapter.ifIndex -eq 8) 'known competition WiFi recognized before DHCP is ready'
    $script:profiles=@(); $script:competitionIp='192.0.2.100'; $script:phoneIp='192.0.2.101'
    Assert-RMThrows { Get-RMPlan $config } 'two competition subnet connections fail clearly without input or network changes'
    $script:phoneIp='198.51.100.2'; $config.AdapterName='Competition Ethernet'
    $config.ClientAdapterName='Competition Ethernet'
    Assert-RMThrows { Get-RMPlan $config -NonInteractive } 'reject two roles on same adapter'
    Assert-RMThrows { Select-RMAdapter '' '203.0.113.2' -NonInteractive } 'ambiguous auto-selection fails before changes'
    $snap=Get-RMAdapterSnapshot $plan[0].Adapter
    Assert-RM ($snap.Dhcp -eq 'Enabled' -and $snap.ManualDns -eq '') 'DHCP DNS origin survives missing NameServer registry value'
    $statePath=Join-Path $scratch 'state.json'
    Enable-RMNetwork $plan $layout $statePath '192.0.2.0/24'
    $state=Get-RMState $statePath
    $created=$state.Created
    Assert-RM ($state.Adapters[0].Name -eq 'Competition Ethernet') 'snapshot saved before mutation'
    Enable-RMNetwork $plan $layout $statePath '192.0.2.0/24'
    Assert-RM ((Get-RMState $statePath).Created -eq $created) 'repeated start preserves original snapshot'
    $otherPlan=@([pscustomobject]@{Adapter=(Get-NetAdapter)[1];Address='192.0.2.2';Prefix=24})
    Assert-RMThrows { Enable-RMNetwork $otherPlan $layout $statePath '192.0.2.0/24' } 'new adapter cannot overwrite active backup'
    $state.Computer='THIS-IS-NOT-THE-LOCAL-MACHINE'
    Save-RMState $statePath $state
    Assert-RMThrows { Get-RMState $statePath } 'cannot restore another computer backup'
    $state.Computer=$env:COMPUTERNAME
    # Static fixture avoids invoking the native DHCP renew in this unit test.
    $state.Adapters[0].Dhcp='Disabled'
    $state.Adapters[0].AutomaticMetric='Disabled'
    $state.Adapters[0].Addresses=@([pscustomobject]@{IPAddress='203.0.113.7';PrefixLength=23;SkipAsSource=$false})
    $state.Adapters[0].Gateways=@([pscustomobject]@{NextHop='203.0.113.1';RouteMetric=42})
    $state.Adapters[0].ManualDns='8.8.8.8'
    $state.Adapters[0].Dns=@('8.8.8.8')
    Save-RMState $statePath $state
    Restore-RMState $statePath
    Assert-RM ($script:calls.Contains('restore-ip:203.0.113.7/23')) 'restore original static IP and prefix'
    Assert-RM ($script:calls.Contains('gateway:203.0.113.1')) 'restore original gateway'
    Assert-RM ($script:calls.Contains('dns:8.8.8.8')) 'restore original manual DNS'
    Assert-RM ((Get-RMState $statePath).Restored) 'successful restore marked complete'
    $count=$script:calls.Count
    Restore-RMState $statePath
    Assert-RM ($script:calls.Count -eq $count) 'second restore is a no-op'
    $state.Restored=$false
    $state.Adapters[0].Dhcp='Enabled'
    $state.Adapters[0].ManualDns=''
    Save-RMState $statePath $state
    Restore-RMState $statePath
    Assert-RM ($script:calls.Contains('renew:Competition Ethernet')) 'DHCP renewal restricted to saved adapter'
    Assert-RM ((Get-RMState $statePath).Restored) 'DHCP restore succeeds'
    $state.Adapters[0].Dhcp='Disabled'
    # Simulate a firewall creation failure and ensure the original static config is recovered.
    $state.Restored=$false
    Save-RMState $statePath $state
    $script:failRule=$true
    Assert-RMThrows { Enable-RMNetwork $plan $layout $statePath '192.0.2.0/24' } 'injected firewall failure is reported'
    Assert-RM ((Get-RMState $statePath).Restored) 'failure rolls back original snapshot'
    # Verify launch ordering and idempotence without opening UI or killing any process.
    $script:started=New-Object 'System.Collections.Generic.List[string]'
    $script:fakeRunning=@{}
    function Test-RMRuntime { param($Layout) }
    function Get-RMProcess { param($Exe)
        if ($script:fakeRunning.ContainsKey($Exe)) { return [pscustomobject]@{ExecutablePath=$Exe} }
        return @()
    }
    function Get-CimInstance { param($ClassName,$Filter) return @() }
    function Start-Process { param($FilePath,$WorkingDirectory,$ArgumentList,$WindowStyle)
        $script:started.Add($FilePath)
        if ($FilePath -eq $layout.Engine) { $script:fakeRunning[$layout.Engine]=$true }
        else {
            if (-not $ArgumentList.Contains($layout.Start)) { throw 'Wrong official start.bat' }
            $script:fakeRunning[$layout.Client]=$true
            $script:fakeRunning[$layout.Daemon]=$true
        }
    }
    Start-RMPrograms $layout
    Assert-RM ($script:started.Count -eq 2 -and $script:started[0] -eq $layout.Engine) 'engine before official start.bat, correct working directories'
    Start-RMPrograms $layout
    Assert-RM ($script:started.Count -eq 2) 'repeated launch does not duplicate official programs'
    $script:fakeRunning.Remove($layout.Daemon)
    Assert-RMThrows { Start-RMPrograms $layout } 'detect running player without daemon'
    $installer=Join-Path $scratch 'fixture-driver.exe'
    Set-Content -LiteralPath $installer -Value 'known installer bytes'
    $hashFile=Join-Path $scratch 'installer-hashes.json'
    @{ 'fixture-driver.exe'=(Get-FileHash -LiteralPath $installer).Hash } | ConvertTo-Json | Set-Content -LiteralPath $hashFile -Encoding UTF8
    $script:signature='Valid'
    function Get-AuthenticodeSignature { param($FilePath) return [pscustomobject]@{Status=$script:signature} }
    Test-RMInstaller $installer $hashFile
    Assert-RM $true 'valid signed installer accepted'
    $script:signature='NotSigned'
    Test-RMInstaller $installer $hashFile
    Assert-RM $true 'known official unsigned wrapper accepted by exact hash'
    Add-Content -LiteralPath $installer -Value 'tampered'
    Assert-RMThrows { Test-RMInstaller $installer $hashFile } 'modified unsigned installer rejected'
    $script:signature='HashMismatch'
    Assert-RMThrows { Test-RMInstaller $installer $hashFile } 'invalid signed installer rejected'
    # Export into the fake kit and ensure wrappers really parse/preserve relative paths.
    & (Join-Path $repo 'scripts\portable\deploy.ps1') -KitRoot $kit
    $wrapper=[IO.File]::ReadAllText((Join-Path $kit '00-启动脚本\0-一键启动.bat'))
    Assert-RM ($wrapper.Contains('%~dp0RM26.ps1') -and -not $wrapper.Contains('21404')) 'portable wrapper independent of owner username'
    $custom=Join-Path $kit '00-启动脚本\settings.json'
    Set-Content -LiteralPath $custom -Value '{"custom": true}'
    & (Join-Path $repo 'scripts\portable\deploy.ps1') -KitRoot $kit
    Assert-RM ((Get-Content $custom -Raw).Contains('custom')) 'upgrade preserves local settings'
    # Exercise the actual organized entry point in a different Unicode/space path.
    # Setup/Restore DryRun never run installers, processes, or network mutations.
    $release=Join-Path $scratch '交付目录 另一台电脑'
    $official=Join-Path $release '03-官方程序'
    New-Item -ItemType Directory -Path $official -Force | Out-Null
    foreach ($category in @('01-引擎','02-选手端')) {
        Copy-Item -LiteralPath (Join-Path $kit $category) -Destination $official -Recurse
    }
    $internal=Join-Path $release '02-运行脚本\Windows\internal'
    $settings=Join-Path $release '06-配置\Windows'
    New-Item -ItemType Directory -Path $internal,$settings -Force | Out-Null
    $bom=New-Object Text.UTF8Encoding($true)
    foreach ($name in @('RM26.ps1','RM26.Common.ps1')) {
        [IO.File]::WriteAllText((Join-Path $internal $name),[IO.File]::ReadAllText((Join-Path $repo "scripts\portable\windows\$name")),$bom)
    }
    [IO.File]::WriteAllText((Join-Path $internal 'project.ps1'),[IO.File]::ReadAllText((Join-Path $repo 'scripts\portable\project.ps1')),$bom)
    Copy-Item -LiteralPath (Join-Path $repo 'scripts\portable\windows\settings.json') -Destination $settings
    Copy-Item -LiteralPath (Join-Path $repo 'scripts\portable\windows\installer-hashes.json') -Destination $settings
    $setupOutput=(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $internal 'project.ps1') -Action Setup -DryRun -NonInteractive | Out-String)
    Assert-RM ($LASTEXITCODE -eq 0 -and $setupOutput.Contains('05-安装包') -and $setupOutput.Contains('06-配置')) 'organized entry resolves relocated installers/config in Unicode path'
    $absentConfig=Join-Path $scratch 'network-config-absent.json'
    $startOutput=(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $internal 'project.ps1') -Action Start -DryRun -NonInteractive -ConfigPath $absentConfig | Out-String)
    Assert-RM ($LASTEXITCODE -eq 0 -and $startOutput.Contains('[DRY RUN] Start')) 'startup works without any competition network configuration'
    $restoreOutput=(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $internal 'project.ps1') -Action Restore -DryRun -NonInteractive | Out-String)
    Assert-RM ($LASTEXITCODE -eq 0 -and $restoreOutput.Contains('[DRY RUN] Restore')) 'organized recovery entry works without starting official software'
    Write-Output "ALL PASSED: $script:passed assertions. Temporary fixtures retained: $scratch"
} catch { Write-Error $_; exit 1 }
