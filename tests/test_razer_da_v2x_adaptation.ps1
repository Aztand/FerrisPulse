# ============================================================================
# 测试脚本: test_razer_da_v2x_adaptation.ps1
# 目标: 验证雷蛇 DeathAdder V2 X HyperSpeed (VID 1532 / PID 009C) 的适配元数据
#   1. PID 型号映射与接收器判定（不依赖电量启发式）
#   2. DPI 能力区间（14K / 50 步进）与回报率档位（非 8K 机型）
#   3. MaxPollingRate 在设备构造路径中被赋值
# 说明: 通过反射直接调用已编译程序集的真实实现，不依赖设备是否插在机器上。
# ============================================================================

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectDir = Resolve-Path "$ScriptDir\.."
Set-Location $ProjectDir

function Fail([string]$msg) {
    Write-Host "FAILED: $msg" -ForegroundColor Red
    exit 1
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " [测试 1/3] 程序集加载与方法可用性" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$asmPath = Join-Path $ProjectDir "FerrisPulse.exe"
if (-not (Test-Path $asmPath)) { Fail "FerrisPulse.exe 不存在，请先执行 build.bat" }
$asm = [System.Reflection.Assembly]::Load([System.IO.File]::ReadAllBytes((Resolve-Path $asmPath).Path))
$t = $asm.GetType("RazerBatteryTray.RazerDeviceHelper")
if ($null -eq $t) { Fail "未找到 RazerBatteryTray.RazerDeviceHelper" }

$bf = [System.Reflection.BindingFlags]'Public,Static'
$mName = $t.GetMethod("GetRazerOfficialModelName", $bf)
$mDongle = $t.GetMethod("DetermineIsDongle", $bf)
$mCap = $t.GetMethod("GetDpiCapability", $bf)
$mRates = $t.GetMethod("GetSupportedPollingRatesForModel", $bf)
$mMax = $t.GetMethod("GetMaxPollingRateForModel", $bf)
foreach ($m in @($mName, $mDongle, $mCap, $mRates, $mMax)) {
    if ($null -eq $m) { Fail "RazerDeviceHelper 缺少必要方法: $($m.Name)" }
}
Write-Host "PASSED: 反射入口齐备" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [测试 2/3] PID 型号映射 / 接收器判定 / DPI 能力 / 回报率档位" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$model = $mName.Invoke($null, @(0x009C, "Razer DeathAdder V2 X HyperSpeed"))
if ($model -ne "Razer DeathAdder V2 X HyperSpeed") { Fail "型号映射错误: $model" }

# 电量 0% 且未充电时，必须仍凭 PID 判定为 2.4G 接收器（纯无线、AA 干电池机型）
$isDongle = $mDongle.Invoke($null, @(0x009C, "Razer DeathAdder V2 X HyperSpeed", 0, $false))
if ($isDongle -ne $true) { Fail "DetermineIsDongle(0x009C) 应返回 true，实际 $isDongle" }

$cap = $mCap.Invoke($null, @("Razer DeathAdder V2 X HyperSpeed", 0x009C))
if ($cap.MinDpi -ne 100) { Fail "DPI 下限错误: $($cap.MinDpi)" }
if ($cap.MaxDpi -ne 14000) { Fail "DPI 上限错误: $($cap.MaxDpi) (期望 14000)" }
if ($cap.Step -ne 50) { Fail "DPI 步进错误: $($cap.Step) (期望 50)" }

$rates = $mRates.Invoke($null, @(0x009C, "Razer DeathAdder V2 X HyperSpeed"))
if (($rates -join ',') -ne "125,250,500,1000") { Fail "回报率档位错误: $($rates -join ',')" }

$maxRate = $mMax.Invoke($null, @(0x009C, "Razer DeathAdder V2 X HyperSpeed"))
if ($maxRate -ne 1000) { Fail "MaxPollingRate 错误: $maxRate (期望 1000)" }

# 8K 机型不得被 14K 分支误伤
$v3pro = $mCap.Invoke($null, @("Razer DeathAdder V3 Pro", 0x00B6))
if ($v3pro.MaxDpi -ne 30000) { Fail "DeathAdder V3 Pro 能力被污染: $($v3pro.MaxDpi)" }
$v3rates = $mRates.Invoke($null, @(0x00B6, "Razer DeathAdder V3 Pro"))
if ($v3rates -notcontains 8000) { Fail "DeathAdder V3 Pro 8K 档位丢失" }

Write-Host ("PASSED: 型号={0} / 接收器={1} / DPI={2}-{3} step{4} / 回报率={5} / max={6}" -f $model, $isDongle, $cap.MinDpi, $cap.MaxDpi, $cap.Step, ($rates -join ','), $maxRate) -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [测试 3/3] MaxPollingRate 构造路径赋值校验" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$src = [System.IO.File]::ReadAllText("$ProjectDir\src\Hardware\RazerDeviceHelper.cs", [System.Text.Encoding]::UTF8)
if (-not $src.Contains("MaxPollingRate = GetMaxPollingRateForModel")) {
    Fail "RazerDeviceHelper 未在设备构造路径设置 MaxPollingRate"
}
$b = [System.IO.File]::ReadAllBytes("$ProjectDir\src\Hardware\RazerDeviceHelper.cs")
if (-not ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) {
    Fail "RazerDeviceHelper.cs 不是 UTF-8 with BOM 编码"
}
Write-Host "PASSED: MaxPollingRate 已赋值，源码编码合规" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host " ALL PASS: DeathAdder V2 X HyperSpeed 适配元数据全部正确！" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
exit 0
