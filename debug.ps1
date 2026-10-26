#Requires -Version 7.0
<#
.SYNOPSIS
  《融点》RONGDIAN 调试速查脚本：一条命令跑游戏、开编辑器、跑无头测试、截图。

.EXAMPLE
  .\debug.ps1 run                 # 直接开游戏窗口
  .\debug.ps1 editor              # 用 Godot 编辑器打开本工程（断点调试走这条）
  .\debug.ps1 test                # 依次跑 6 个无头测试，汇总 PASS/FAIL
  .\debug.ps1 test smoke          # 只跑名字里含 smoke 的测试
  .\debug.ps1 shot -Only 01,08 -NoHud   # 只拍 01/08 号机位，藏掉 HUD
  .\debug.ps1 probe probe8        # 跑 tools/probe8.tscn（做一个数值探针）
  .\debug.ps1 userdata            # 打开 user:// 目录（存档、日志）
  .\debug.ps1 where               # 只打印检测到的 Godot 路径
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = 'help',

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Rest = @(),

    # shot 专用
    [string]$Only = '',
    [string]$Tag = 'dev',
    [string]$Hour = '',
    [switch]$NoHands,
    [switch]$NoHud
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$AllTests = @('smoke_test', 'intro_test', 'control_test', 'reload_test', 'content_test', 'systems_test')

# ---------------------------------------------------------------- Godot 定位
# 本机 Godot 的目录名就叫 ..._win64.exe（是目录不是文件），所以按目录名模糊找，
# 再在目录里挑带 console 的那个：无头测试要它才能把 stdout 接回终端。
function Find-Godot([bool]$NeedConsole) {
    $explicit = if ($env:GODOT_BIN) { $env:GODOT_BIN } elseif ($env:GODOT4_BIN) { $env:GODOT4_BIN } else { '' }
    if ($explicit) {
        if (-not (Test-Path $explicit)) { throw "GODOT_BIN 指向的文件不存在：$explicit" }
        return (Resolve-Variant $explicit $NeedConsole)
    }

    foreach ($n in @('godot', 'godot4', 'godot.exe')) {
        $c = Get-Command $n -ErrorAction SilentlyContinue
        if ($c) { return (Resolve-Variant $c.Source $NeedConsole) }
    }

    $searchRoots = @(
        'D:\WorkSpace', 'D:\Godot', 'D:\Tools', 'D:\Program Files',
        'C:\Program Files', 'C:\Program Files (x86)',
        (Join-Path $env:LOCALAPPDATA 'Programs'),
        $env:USERPROFILE
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($r in $searchRoots) {
        $hits = Get-ChildItem -LiteralPath $r -Filter 'Godot*' -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                Get-ChildItem -LiteralPath $_.FullName -Filter '*.exe' -File -ErrorAction SilentlyContinue
            }
        $hits += Get-ChildItem -LiteralPath $r -Filter 'Godot*.exe' -File -ErrorAction SilentlyContinue
        $pick = $hits | Where-Object { $_.Name -match 'win64' -and $_.Name -notmatch 'console' } |
            Sort-Object Length -Descending | Select-Object -First 1
        if ($pick) { return (Resolve-Variant $pick.FullName $NeedConsole) }
    }
    throw "没找到 Godot。装一个，或设置环境变量 GODOT_BIN 指向 godot.exe。"
}

# 给定任意一个 Godot exe，按需要返回带 console 的兄弟文件
function Resolve-Variant([string]$exe, [bool]$NeedConsole) {
    if (-not $NeedConsole) { return $exe }
    $dir = Split-Path $exe
    $console = Get-ChildItem -LiteralPath $dir -Filter '*console*.exe' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($console) { return $console.FullName }
    return $exe
}

# 噪音过滤：headless 退出时 Godot 自己会报一堆 RID/ObjectDB 泄漏，和工程无关
function Clean-Output([string]$text) {
    $noise = 'RID allocations of type|Leaked instance dependency|ObjectDB instances were leaked|' +
             'resources still in use at exit|at: ~Dependency|at: cleanup \(core/object|at: clear \(core/io/resource'
    ($text -split "`r?`n") | Where-Object { $_ -notmatch $noise }
}

function Invoke-Godot([string]$exe, [string[]]$GodotArgs) {
    $lines = & $exe @GodotArgs 2>&1 | ForEach-Object { "$_" }
    return [pscustomobject]@{ Code = $LASTEXITCODE; Text = ($lines -join "`n") }
}

# ---------------------------------------------------------------- 命令实现
function Show-Help {
    Write-Host @"
《融点》调试速查

  .\debug.ps1 run                      开游戏（窗口）
  .\debug.ps1 editor                   用编辑器打开工程（断点/单步/看变量）
  .\debug.ps1 test [关键词...]          跑无头测试并汇总（不带参数 = 全部 6 个）
  .\debug.ps1 shot [-Only 01,08] [-Tag v1] [-Hour 20] [-NoHud] [-NoHands]
                                       截图到 tools/shots/
  .\debug.ps1 probe <名字>              跑 tools/<名字>.tscn 探针
  .\debug.ps1 scene <名字> [--参数]     跑任意场景（无头）
  .\debug.ps1 userdata                 打开 user:// 目录（存档/日志）
  .\debug.ps1 where                    打印检测到的 Godot 版本与路径

注意：无头测试要写 user://（%APPDATA%\Godot\app_userdata\），
      沙箱只读时「存档」用例会假失败。
环境变量 GODOT_BIN 可指定 Godot 可执行文件，跳过自动探测。
"@ -ForegroundColor Gray
}

function Invoke-Tests([string[]]$Filter) {
    $names = if ($Filter.Count -gt 0) {
        $AllTests | Where-Object { $n = $_; $Filter | Where-Object { $n -like "*$_*" } }
    } else { $AllTests }
    if (-not $names) { throw "没有匹配的测试。可选：$($AllTests -join ', ')" }

    $exe = Find-Godot $true
    Write-Host "Godot: $exe" -ForegroundColor DarkGray
    $results = @()
    foreach ($name in $names) {
        if (-not (Test-Path (Join-Path $Root "$name.tscn"))) {
            Write-Host ("  {0,-14} 跳过（没有 {0}.tscn）" -f $name) -ForegroundColor DarkYellow
            continue
        }
        Write-Host ("  {0,-14} 运行中…" -f $name) -NoNewline -ForegroundColor DarkGray
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-Godot $exe @('--headless', '--path', $Root, "res://$name.tscn")
        $sw.Stop()
        $clean = Clean-Output $r.Text
        $ok = ($r.Code -eq 0)
        $results += [pscustomobject]@{ Name = $name; Ok = $ok; Code = $r.Code; Secs = [math]::Round($sw.Elapsed.TotalSeconds, 1); Lines = $clean }
        $mark = if ($ok) { 'PASS' } else { 'FAIL' }
        $color = if ($ok) { 'Green' } else { 'Red' }
        Write-Host ("`r  {0,-14} {1}  {2,5:N1}s  exit={3}" -f $name, $mark, $sw.Elapsed.TotalSeconds, $r.Code) -ForegroundColor $color
        if (-not $ok) {
            $clean | Where-Object { $_ -match '^\s*-\s|SCRIPT ERROR|Parse Error|===== 失败|=====失败' } | ForEach-Object {
                Write-Host "      $_" -ForegroundColor DarkRed
            }
        }
    }

    $pass = ($results | Where-Object Ok).Count
    Write-Host ""
    Write-Host ("  结果：$pass / $($results.Count) 通过") -ForegroundColor $(if ($pass -eq $results.Count) { 'Green' } else { 'Red' })
    if ($pass -ne $results.Count) {
        $failed = ($results | Where-Object { -not $_.Ok }).Name -join ', '
        Write-Host "  失败：$failed" -ForegroundColor Red
        Write-Host "  看完整输出：.\debug.ps1 test <名字>；或 .\debug.ps1 editor 下断点。" -ForegroundColor DarkGray
        exit 1
    }
}

# ---------------------------------------------------------------- 分发
switch ($Command.ToLower()) {
    'run' {
        $exe = Find-Godot $false
        & $exe --path $Root @Rest
    }
    'editor' { & (Find-Godot $false) -e --path $Root @Rest }
    'test' { Invoke-Tests $Rest }
    'shot' {
        $args2 = @('--path', $Root, 'res://tools/shot.tscn', '--', "--tag=$Tag")
        if ($Only) { $args2 += "--only=$Only" }
        if ($Hour) { $args2 += "--hour=$Hour" }
        if ($NoHands) { $args2 += '--nohands' }
        if ($NoHud) { $args2 += '--nohud' }
        Write-Host "截图 → tools/shots/  tag=$Tag" -ForegroundColor DarkGray
        & (Find-Godot $false) @args2
    }
    'probe' {
        if (-not $Rest) { throw '用法：.\debug.ps1 probe <名字>   例：.\debug.ps1 probe probe8' }
        $name = $Rest[0]
        $scene = if (Test-Path (Join-Path $Root "tools/$name.tscn")) { "res://tools/$name.tscn" }
                 else { "res://$name.tscn" }
        & (Find-Godot $true) --headless --path $Root $scene -- @($Rest | Select-Object -Skip 1)
    }
    'scene' {
        if (-not $Rest) { throw '用法：.\debug.ps1 scene <场景名> [-- 参数]' }
        $name = $Rest[0]
        $scene = if (Test-Path (Join-Path $Root "$name.tscn")) { "res://$name.tscn" } else { "res://tools/$name.tscn" }
        & (Find-Godot $true) --headless --path $Root $scene -- @($Rest | Select-Object -Skip 1)
    }
    'userdata' {
        $dir = Join-Path $env:APPDATA 'Godot\app_userdata'
        $proj = Join-Path $dir '融点 RONGDIAN'
        if (-not (Test-Path $proj)) {
            $proj = (Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue |
                     Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
        }
        if ($proj) { Write-Host $proj; Start-Process explorer.exe $proj }
        else { Write-Host "还没有 user:// 目录（先 run 一次）。" -ForegroundColor DarkYellow }
    }
    'where' {
        $exe = Find-Godot $false
        Write-Host "Godot: $exe"
        & $exe --version
    }
    default { Show-Help }
}
