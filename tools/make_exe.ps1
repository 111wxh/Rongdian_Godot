#Requires -Version 7.0
<#
.SYNOPSIS
    把《融点 RONGDIAN》打包成单文件 Windows 可执行文件（内嵌 pck）。

.DESCRIPTION
    在暂存目录里做一次「干净导出」：只复制运行期真正需要的文件，
    自动剔除 6 个测试场景、tools/、debug.ps1、README、编辑器缓存等开发用文件，
    然后把 build/Rongdian.exe 打出来。

    需要：
      - Godot 4.x 引擎（标准版即可；脚本会自动探测，也可用 $env:GODOT_BIN 指定）
      - 已安装同版本的导出模板（编辑器里「管理导出模板」下载一次，
        或只取 Windows 模板：把 windows_release_x86_64.exe 放到
        %APPDATA%\Godot\export_templates\<版本>\ 下）

.EXAMPLE
    .\tools\make_exe.ps1
    .\tools\make_exe.ps1 -Out D:\dist\Rongdian.exe
#>
[CmdletBinding()]
param(
    [string]$Out = '',
    [switch]$KeepStage
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $Out) { $Out = Join-Path $root 'build\Rongdian.exe' }
$Out = [System.IO.Path]::GetFullPath($Out)
$stage = Join-Path $root 'build\_stage'

function Find-Godot {
    foreach ($cand in @($env:GODOT_BIN, $env:GODOT4_BIN)) {
        if ($cand -and (Test-Path $cand)) { return $cand }
    }
    foreach ($name in @('godot', 'godot4', 'godot.exe')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    $roots = @('D:\WorkSpace', 'D:\Godot', 'D:\Tools', 'D:\GameDev', 'C:\Program Files', 'C:\Program Files (x86)', (Join-Path $env:USERPROFILE 'Desktop'), (Join-Path $env:USERPROFILE 'Downloads'))
    $hits = foreach ($r in $roots) {
        if (Test-Path $r) {
            Get-ChildItem -Path $r -Recurse -Depth 2 -Filter 'Godot*win64*.exe' -File -ErrorAction SilentlyContinue
        }
    }
    $hits = @($hits | Where-Object { $_.Name -notmatch 'console' } | Sort-Object { $_.VersionInfo.FileVersion } -Descending)
    if ($hits.Count -gt 0) { return $hits[0].FullName }
    throw '找不到 Godot。请设置 $env:GODOT_BIN 指向 godot 可执行文件。'
}

function Resolve-GodotExe([string]$base) {
    # 导出必须走 console 版，否则进程立刻返回且没有输出
    $dir = Split-Path $base -Parent
    $console = Get-ChildItem -Path $dir -Filter '*console*.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($console) { return $console.FullName }
    return $base
}

$godot = Find-Godot
$godotExe = Resolve-GodotExe $godot
Write-Host "引擎: $godotExe"
$ver = (& $godotExe --version) 2>$null | Select-Object -First 1
Write-Host "版本: $ver"

# ---- 1. 准备暂存目录 -------------------------------------------------------
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $Out -Parent) -Force | Out-Null

$excludeDirs = @('.git', 'build', '.tools', '_backup_orig', 'tools')
$excludeNames = @('*_test.gd', '*_test.gd.uid', '*_test.tscn', '*_test.tscn.remap',
                  'debug.ps1', 'README.md', 'LICENSE', '合并记录.md', '.gitignore', '.gitattributes')

Write-Host '复制工程到暂存目录……'
Get-ChildItem -Path $root -Force | Where-Object { $excludeDirs -notcontains $_.Name } | ForEach-Object {
    Copy-Item $_.FullName -Destination $stage -Recurse -Force
}
# 编辑器缓存（folding/layout 等）不需要进包
$editorCache = Join-Path $stage '.godot\editor'
if (Test-Path $editorCache) { Remove-Item $editorCache -Recurse -Force }
Get-ChildItem -Path $stage -Filter '*_test.*' -File | Remove-Item -Force
foreach ($n in $excludeNames) {
    Get-ChildItem -Path $stage -Filter $n -File -ErrorAction SilentlyContinue | Remove-Item -Force
}

$staged = (Get-ChildItem $stage -Recurse -File | Measure-Object -Property Length -Sum)
Write-Host ("暂存目录: {0} 个文件 / {1:N1} MB" -f $staged.Count, ($staged.Sum / 1MB))

# ---- 2. 导出 --------------------------------------------------------------
if (Test-Path $Out) { Remove-Item $Out -Force }
Write-Host "导出到: $Out"
$log = & $godotExe --headless --path $stage --export-release 'Windows Desktop' $Out 2>&1
$code = $LASTEXITCODE
$errors = $log | Where-Object { $_ -match 'ERROR|SCRIPT ERROR' -and $_ -notmatch 'root certificate|RID allocations|Leaked instance|ObjectDB' }
if ($errors) { $errors | Select-Object -First 10 | ForEach-Object { Write-Warning $_ } }
if ($code -ne 0) { throw "导出失败，退出码 $code" }
if (-not (Test-Path $Out)) { throw "导出没有产出文件：$Out" }

$size = (Get-Item $Out).Length
Write-Host ("输出: {0} （{1:N1} MB）" -f $Out, ($size / 1MB))
if ($size -lt 40MB) { Write-Warning '文件明显偏小，可能是导出模板没装好。' }

if (-not $KeepStage) { Remove-Item $stage -Recurse -Force }
Write-Host '完成。'
