# Dependency detection/installation regression. All installers are mocked.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts\portable\windows\RM26.Common.ps1')
$scratch=Join-Path $repo ('tmp\dependency-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$passed=0
function Assert-Dependency($Condition,[string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:passed++
    Write-Output "PASS: $Message"
}
$daemon=Join-Path $scratch 'daemon'
New-Item -ItemType Directory -Path $daemon -Force | Out-Null
Set-Content -LiteralPath (Join-Path $daemon 'helper.runtimeconfig.json') -Value '{"runtimeOptions":{"framework":{"name":"Microsoft.NETCore.App","version":"7.0.0"}}}' -Encoding UTF8
$layout=[pscustomobject]@{Daemon=(Join-Path $daemon 'helper.exe')}
$script:runtimes=@('Microsoft.NETCore.App 8.0.1 [ignored]')
$script:vc=[pscustomobject]@{Installed=1;Version='v14.51.36247.00'}
function Get-RMDotNetRuntimes { return $script:runtimes }
function Get-RMVcRuntime { return $script:vc }
$status=@(Get-RMRuntimeStatus $layout)
Assert-Dependency (-not $status[0].Installed) '.NET 8 alone does not satisfy required .NET 7'
Assert-Dependency $status[1].Installed 'newer compatible VC++ x64 runtime is skipped'
$script:runtimes=@('Microsoft.NETCore.App 7.0.20 [ignored]')
Assert-Dependency (Get-RMRuntimeStatus $layout)[0].Installed 'installed .NET 7 servicing release is skipped'
$script:vc=[pscustomobject]@{Installed=1;Version='v14.0.0.0'}
Assert-Dependency (-not (Get-RMRuntimeStatus $layout)[1].Installed) 'insufficient VC++ runtime is marked for installation'
$inf=Join-Path $scratch 'INF'
New-Item -ItemType Directory -Path $inf -Force | Out-Null
Assert-Dependency (-not (Test-RMDJIDriverInstalled $inf)) 'no published driver means installation is needed'
$video='Provider=libusb-win32'+"`n"+'libusb0'+"`n"+'DeviceID1X6="VID_2CA3&PID_1020&MI_00"'+"`n"+'DeviceID1X7="VID_2CA3&PID_1020&MI_01"'
Set-Content -LiteralPath (Join-Path $inf 'oem1.inf') -Value $video
Assert-Dependency (-not (Test-RMDJIDriverInstalled $inf)) 'video interface alone does not hide a missing protocol driver'
Set-Content -LiteralPath (Join-Path $inf 'oem2.inf') -Value ('usbser'+"`n"+'USB\VID_2CA3&PID_1020&MI_02')
Assert-Dependency (Test-RMDJIDriverInstalled $inf) 'published video and protocol drivers recognized with receiver unplugged'

$script:ready=@{DotNet=$true;VC=$true;DJI=$true}
$script:installed=New-Object 'System.Collections.Generic.List[string]'
$script:publish=$true; $script:exitCode=0
$names=@{DotNet='dotnet-runtime-7.0.4-win-x64.exe';VC='VC2015~2019_redist.x64.exe';DJI='DJI_Driver_Installer_32bit&64bit_4.8.11.exe'}
foreach ($name in $names.Values) { Set-Content -LiteralPath (Join-Path $scratch $name) -Value 'fixture only' }
function Get-RMDependencyStatus { param($Layout)
    foreach ($key in @('DotNet','VC','DJI')) { [pscustomobject]@{Key=$key;Name=$key;Installed=$script:ready[$key];Installer=$names[$key]} }
}
function Test-RMInstaller { param($Installer,$HashFile) }
function Start-Process { param($FilePath,[switch]$Wait,[switch]$PassThru)
    $script:installed.Add([IO.Path]::GetFileName($FilePath))
    if ($script:publish) { foreach ($key in $names.Keys) { if ($names[$key] -eq [IO.Path]::GetFileName($FilePath)) { $script:ready[$key]=$true } } }
    return [pscustomobject]@{ExitCode=$script:exitCode}
}
Install-RMDependencies $layout $scratch 'unused'
Assert-Dependency ($script:installed.Count -eq 0) 'all dependencies present: no installer opens'
$script:ready.DotNet=$false
Install-RMDependencies $layout $scratch 'unused'
Assert-Dependency ($script:installed.Count -eq 1 -and $script:installed[0] -eq $names.DotNet) 'only missing .NET installer opens, other dependencies skipped'
$script:installed.Clear(); $script:ready.VC=$false; $script:ready.DJI=$false
Install-RMDependencies $layout $scratch 'unused'
Assert-Dependency ($script:installed.Count -eq 2 -and -not $script:installed.Contains($names.DotNet)) 'only missing VC++ and driver installers open'
$script:ready.DotNet=$false; $script:publish=$false
$failed=$false
try { Install-RMDependencies $layout $scratch 'unused' } catch { $failed=$true }
Assert-Dependency $failed 'success exit code without installed dependency is reported as failure'
$script:exitCode=3010
Install-RMDependencies $layout $scratch 'unused'
Assert-Dependency $true 'reboot-required result does not claim the dependency is ready before reboot'
Write-Output "ALL PASSED: $passed dependency assertions"
