# Copy the maintained scripts into an existing, complete official tools kit.
[CmdletBinding()]
param([string]$KitRoot='')
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$sourceParent=Split-Path $repo -Parent
$project=Split-Path $sourceParent -Parent
$source=Join-Path $PSScriptRoot 'windows'
$utf8Bom=New-Object Text.UTF8Encoding($true)
if (-not $KitRoot -and (Split-Path $repo -Leaf) -eq '源码' -and (Split-Path $sourceParent -Leaf) -eq '04-自定义客户端' -and
    (Test-Path -LiteralPath (Join-Path $project '02-运行脚本\Windows\internal') -PathType Container)) {
    $target=Join-Path $project '02-运行脚本\Windows\internal'
    foreach ($file in @((Join-Path $source 'RM26.ps1'),(Join-Path $source 'RM26.Common.ps1'),(Join-Path $PSScriptRoot 'project.ps1'))) {
        [IO.File]::WriteAllText((Join-Path $target (Split-Path $file -Leaf)),[IO.File]::ReadAllText($file),$utf8Bom)
    }
    Write-Output "Deployed: $target"
    return
}
if (-not $KitRoot) { $KitRoot=Join-Path $repo 'RM26_工具' }
$KitRoot=[IO.Path]::GetFullPath($KitRoot)
if (-not (Test-Path -LiteralPath $KitRoot -PathType Container)) { throw "Kit directory does not exist: $KitRoot" }
. (Join-Path $source 'RM26.Common.ps1')
$null=Get-RMLayout $KitRoot
$target=Join-Path $KitRoot '00-启动脚本'
$backup=Join-Path $KitRoot ('08-历史备份\scripts-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
if (Test-Path -LiteralPath $target) {
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    Copy-Item -LiteralPath $target -Destination $backup -Recurse
}
New-Item -ItemType Directory -Path $target -Force | Out-Null
foreach ($file in Get-ChildItem -LiteralPath $source -File) {
    # User's selected adapter settings survive script upgrades.
    if ($file.Name -eq 'settings.json' -and (Test-Path -LiteralPath (Join-Path $target $file.Name))) { continue }
    $content=[IO.File]::ReadAllText($file.FullName)
    [IO.File]::WriteAllText((Join-Path $target $file.Name),$content,$utf8Bom)
}
$actions=[ordered]@{
    '0-一键启动.bat'='Start'; '1-切到引擎局域网.bat'='Network'
    '2-切回自动获取.bat'='Restore'; '3-一键还原.bat'='Restore -StopPrograms'
    '4-首次依赖安装.bat'='Setup'; '5-诊断.bat'='Status'; '6-只关闭官方程序.bat'='Stop'
    '7-应急恢复DHCP.bat'='Dhcp'
}
foreach ($name in $actions.Keys) {
    # ASCII batch content avoids code-page corruption. %~dp0 supports spaces, Chinese paths and other drives.
    $batch="@echo off`r`nsetlocal`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0RM26.ps1`" -Action $($actions[$name]) %*`r`nset `"rc=%errorlevel%`"`r`nif not `"%rc%`"==`"0`" echo Operation failed. Exit code: %rc%`r`npause`r`nexit /b %rc%`r`n"
    [IO.File]::WriteAllText((Join-Path $target $name),$batch,[Text.Encoding]::ASCII)
}
$guide=Join-Path $PSScriptRoot 'README.md'
Copy-Item -LiteralPath $guide -Destination (Join-Path $target '启动流程.md') -Force
[IO.File]::WriteAllText((Join-Path $target 'README-脚本说明.txt'),"请打开同目录的 启动流程.md。旧说明已由便携版流程替换。`r`n",$utf8Bom)
$linuxDir=Join-Path $KitRoot '09-Linux客户端'
New-Item -ItemType Directory -Path $linuxDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'linux\rm26-client.sh') -Destination $linuxDir -Force
Copy-Item -LiteralPath $guide -Destination (Join-Path $KitRoot '使用说明.md') -Force
Write-Output "Deployed: $target"
Write-Output "Previous scripts backup: $backup"
