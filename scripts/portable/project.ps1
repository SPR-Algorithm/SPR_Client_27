[CmdletBinding()]
param(
    [ValidateSet('Start','Network','Restore','Stop','Status','Setup','Dhcp','Custom')][string]$Action='Status',
    [switch]$DryRun,
    [switch]$NonInteractive,
    [string]$ConfigPath=''
)
# Supports both the development tree and the organized delivery tree.
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$release=Split-Path $repo -Parent
$sourceParent=Split-Path $repo -Parent
if ((Split-Path $repo -Leaf) -eq '源码' -and (Split-Path $sourceParent -Leaf) -eq '04-自定义客户端') {
    $release=Split-Path $sourceParent -Parent
}
$organized=Test-Path -LiteralPath (Join-Path $release '03-官方程序') -PathType Container
if ($Action -eq 'Custom') {
    $appFolder=Join-Path $release '04-自定义客户端\Windows'
    $executable=Join-Path $appFolder 'RoboMasterClient2025.exe'
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw "Windows custom client not found: $executable. Extract the complete project first."
    }
    if ($DryRun) { Write-Host "[DRY RUN] Custom: $executable"; exit 0 }
    Start-Process -FilePath $executable -WorkingDirectory $appFolder
    exit 0
}
if ($organized) {
    $kit=Join-Path $release '03-官方程序'
    $entry=Join-Path $release '02-运行脚本\Windows\internal\RM26.ps1'
    if (-not $ConfigPath) { $ConfigPath=Join-Path $release '06-配置\Windows\settings.json' }
} else {
    $kit=Join-Path $repo 'RM26_工具'
    $entry=Join-Path $kit '00-启动脚本\RM26.ps1'
}
if (-not (Test-Path -LiteralPath $entry)) { throw "Missing bundled launcher: $entry. Copy the complete project folder." }
$options=@{Action=$Action; KitRoot=$kit; DryRun=$DryRun; NonInteractive=$NonInteractive}
if ($organized) {
    $options.InstallerRoot=Join-Path $release '05-安装包\Windows'
    $options.InstallerHashPath=Join-Path $release '06-配置\Windows\installer-hashes.json'
}
if ($Action -eq 'Restore') { $options.StopPrograms=$true }
if ($ConfigPath) { $options.ConfigPath=[IO.Path]::GetFullPath($ConfigPath) }
& $entry @options
exit $LASTEXITCODE
