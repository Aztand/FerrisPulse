# tests\test_game_opt_osd_anti_override.ps1
# 验证：
# 进入游戏时，完整的回报率和 DPI 自动切换 OSD (ShowGameOptimization / isDualOptimizationMode)
# 绝不会被随后的硬件 OnDpiChanged -> ShowDpi 顶替覆盖！

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$asmPath = Join-Path $PSScriptRoot "..\FerrisPulse.exe"
if (-not (Test-Path $asmPath)) { $asmPath = "FerrisPulse.exe" }
$fullPath = (Resolve-Path $asmPath).Path
$bytes = [System.IO.File]::ReadAllBytes($fullPath)
$asm = [System.Reflection.Assembly]::Load($bytes)

$tOsd = $asm.GetType("RazerBatteryTray.DpiOsdForm")
$tMain = $asm.GetType("RazerBatteryTray.MainForm")
$tInfo = $asm.GetType("RazerBatteryTray.MouseBatteryInfo")
$tCat = $asm.GetType("RazerBatteryTray.DeviceCategory")

# --- 测试 1: DpiOsdForm 处于双开全屏游戏优化模式时，防 ShowDpi 与 ShowRate 顶替 ---
Write-Host "--- 测试 1: DpiOsdForm 双开卡片防 ShowDpi 顶替保护 ---" -ForegroundColor Cyan

$osd = [Activator]::CreateInstance($tOsd, @([float]1.0))
$null = $osd.Handle

function Get-OsdField($name) {
    $f = $tOsd.GetField($name, [System.Reflection.BindingFlags]'Instance,NonPublic')
    if ($f -ne $null) {
        return $f.GetValue($osd)
    }
    return $null
}

# 1. 触发双开电竞卡片 (showDpi=true, showRate=true)
$osd.ShowGameOptimization($true, $true, 3000, 2250, 4, 5, $true, 4000, "Razer")

$isDual = Get-OsdField "isDualOptimizationMode"
if (-not $isDual) {
    Write-Host "FAIL: ShowGameOptimization 未进入 isDualOptimizationMode！" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: 成功激活 isDualOptimizationMode 双开卡片" -ForegroundColor Green

# 2. 在展示计时器生效期间，模拟硬件线程调用 ShowDpi
$osd.ShowDpi(3000, 2250, 4, 5, "Razer")

$isDualAfterDpi = Get-OsdField "isDualOptimizationMode"
if (-not $isDualAfterDpi) {
    Write-Host "FAIL: ShowDpi 冲破了保护，将双开电竞卡片顶替成了常规 DPI 窗口！" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: ShowDpi 被成功拦截，双开电竞卡片依然处于激活状态！" -ForegroundColor Green

# 3. 模拟调用 ShowRate
$osd.ShowRate(4000, "电竞回报率", "Razer")

$isDualAfterRate = Get-OsdField "isDualOptimizationMode"
if (-not $isDualAfterRate) {
    Write-Host "FAIL: ShowRate 顶替了双开电竞卡片！" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: ShowRate 被成功拦截，双开电竞卡片完好保留！" -ForegroundColor Green

# 4. 卡片隐藏后，后续的单 DPI 切换应恢复正常
$osd.HideOsd()
$osd.ShowDpi(1600, 1600, 3, 5, "Razer")

$isDualReset = Get-OsdField "isDualOptimizationMode"
$curDpi = Get-OsdField "currentDpi"
if ($isDualReset -or $curDpi -ne 1600) {
    Write-Host "FAIL: 隐藏后单 DPI 切换未正常响应！" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: 卡片隐藏后恢复常规单 DPI 响应（当前 DPI: $curDpi）" -ForegroundColor Green
$osd.Dispose()


# --- 测试 2: MainForm 中 OnDpiChanged 抑制窗口 ---
Write-Host "`n--- 测试 2: MainForm 中 OnDpiChanged 处于游戏优化静默期时跳过 ShowDpi ---" -ForegroundColor Cyan

$mainForm = [Activator]::CreateInstance($tMain, @($false))
$null = $mainForm.Handle

$fOsd = $tMain.GetField("osdForm", [System.Reflection.BindingFlags]'Instance,NonPublic')
$fGameTime = $tMain.GetField("lastGameOptOsdTime", [System.Reflection.BindingFlags]'Instance,NonPublic')
$mOnDpi = $tMain.GetMethod("OnDpiChanged", [System.Reflection.BindingFlags]'Instance,NonPublic', $null, [Type[]]@([string], [int], [int], [int], [string], [int]), $null)

$subOsd = $fOsd.GetValue($mainForm)
$subOsd.ShowGameOptimization($true, $true, 3000, 2250, 4, 5, $true, 4000, "Razer")

# 设置最近刚刚触发游戏优化 OSD
$fGameTime.SetValue($mainForm, [DateTime]::Now)

# 模拟 DpiMonitorWorker 传入的硬件 DPI 变更通知
$mOnDpi.Invoke($mainForm, @("Razer", 3000, 4, 5, "Razer:1532:00B7", 2250))

$fDualMode = $tOsd.GetField("isDualOptimizationMode", [System.Reflection.BindingFlags]'Instance,NonPublic')
$isStillDual = $fDualMode.GetValue($subOsd)

if (-not $isStillDual) {
    Write-Host "FAIL: OnDpiChanged 触发了 ShowDpi 并破坏了游戏优化 OSD！" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: OnDpiChanged 在静默期内完美跳过了 ShowDpi，全屏游戏优化双开卡片完好无损！" -ForegroundColor Green

$mainForm.Dispose()

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host " ALL PASS: 全屏游戏优化 OSD 防顶替机制验证全部通过！" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
exit 0
