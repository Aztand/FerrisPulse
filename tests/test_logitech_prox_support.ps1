# ============================================================================
# 测试脚本: test_logitech_prox_support.ps1
# 目标: 验证罗技 G PRO X Wireless 游戏耳机 (046D:0ABA) HID++ 4.2 专属适配层：
#   1. 源码 UTF-8 BOM 与 C# 5.0 语法铁律
#   2. Feature 0x1F20 ADC 报文解析断言 (毫伏电压与充电标志位)
#   3. 锂电池放电曲线换算 (ProXVoltageToPercent 线性插值与边界截断)
#   4. 官方型号名称与设备分类 (DeviceCategory.Headset) 反射断言
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
Write-Host " [测试 1/4] 文件存在性与 UTF-8 with BOM 编码校验" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$helperPath = "$ProjectDir\src\Hardware\LogitechDeviceHelper.cs"
if (-not (Test-Path $helperPath)) { Fail "src\Hardware\LogitechDeviceHelper.cs 不存在！" }

$bytes = [System.IO.File]::ReadAllBytes($helperPath)
if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
    Fail "LogitechDeviceHelper.cs 不是 UTF-8 with BOM 编码！"
}
Write-Host "PASSED: LogitechDeviceHelper.cs 编码合规" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [测试 2/4] C# 5.0 语法铁律与协议常量审查" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$content = [System.IO.File]::ReadAllText($helperPath, [System.Text.Encoding]::UTF8)
if ([regex]::IsMatch($content, '\$".*?"')) { Fail "发现禁用的字符串插值语法" }
if ([regex]::IsMatch($content, '\w+\?\.')) { Fail "发现禁用的空条件运算符" }
if ([regex]::IsMatch($content, 'nameof\s*\(')) { Fail "发现禁用的 nameof 语法" }
if ([regex]::IsMatch($content, 'out\s+var\s+')) { Fail "发现禁用的 out var 内联声明" }
if (-not $content.Contains("⚠️ AI 维护准则 (AI MAINTENANCE DIRECTIVE - DO NOT REMOVE) ⚠️")) {
    Fail "缺少头部 AI 维护准则声明"
}

foreach ($token in @("0x0ABA", "0x1F20", "ParseProXAdcPayload", "ProXVoltageToPercent", "QueryLogitechProXHeadset")) {
    if (-not $content.Contains($token)) { Fail "缺少必要方法或常量: $token" }
}
Write-Host "PASSED: 语法与协议特征审查全部通过" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [测试 3/4] 编译并使用全内存反射校验 ADC 解析与放电曲线" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$binPath = "$ProjectDir\FerrisPulse.exe"
if (-not (Test-Path $binPath)) {
    Write-Host "编译二进制以供测试反射..." -ForegroundColor Yellow
    cmd /c "$ProjectDir\build.bat" | Out-Null
}

$asmBytes = [System.IO.File]::ReadAllBytes($binPath)
$asm = [System.Reflection.Assembly]::Load($asmBytes)
$t = $asm.GetType("RazerBatteryTray.LogitechDeviceHelper")
if ($null -eq $t) { Fail "未找到 RazerBatteryTray.LogitechDeviceHelper 类型" }

$bf = [System.Reflection.BindingFlags]'Public,Static'

# 1. 测试 ParseProXAdcPayload(byte[] payload, out int millivolts, out int flags)
$mParse = $t.GetMethod("ParseProXAdcPayload", $bf)
if ($null -eq $mParse) { Fail "未找到 ParseProXAdcPayload 方法" }

# 测试用例 A: 正常放电 4000mV (0x0F 0xA0), flags=0x01 (有效, 未充电)
$argsA = [object[]]@( [byte[]]@(0x0F, 0xA0, 0x01), 0, 0 )
$okA = [bool]$mParse.Invoke($null, $argsA)
if (-not $okA -or [int]$argsA[1] -ne 4000 -or [int]$argsA[2] -ne 1) {
    Fail "ParseProXAdcPayload 测试用例 A 失败: ok=$okA, mv=$($argsA[1]), flags=$($argsA[2])"
}

# 测试用例 B: 充电中 3850mV (0x0F 0x0A), flags=0x03 (有效, 充电中)
$argsB = [object[]]@( [byte[]]@(0x0F, 0x0A, 0x03), 0, 0 )
$okB = [bool]$mParse.Invoke($null, $argsB)
if (-not $okB -or [int]$argsB[1] -ne 3850 -or [int]$argsB[2] -ne 3) {
    Fail "ParseProXAdcPayload 测试用例 B 失败: ok=$okB, mv=$($argsB[1]), flags=$($argsB[2])"
}

# 测试用例 C: 超限电压拒绝 (<2500mV 或 >4300mV)
$argsC1 = [object[]]@( [byte[]]@(0x05, 0x00, 0x01), 0, 0 ) # 1280mV
$okC1 = [bool]$mParse.Invoke($null, $argsC1)
$argsC2 = [object[]]@( [byte[]]@(0x12, 0x00, 0x01), 0, 0 ) # 4608mV
$okC2 = [bool]$mParse.Invoke($null, $argsC2)
if ($okC1 -or $okC2) { Fail "ParseProXAdcPayload 未安全拒绝超限异常电压！" }

# 2. 测试 ProXVoltageToPercent(int millivolts)
$mVolt = $t.GetMethod("ProXVoltageToPercent", $bf)
if ($null -eq $mVolt) { Fail "未找到 ProXVoltageToPercent 方法" }

$tests = @(
    @{ Mv = 4300; Expected = 100 },
    @{ Mv = 4200; Expected = 100 },
    @{ Mv = 4150; Expected = 95 },
    @{ Mv = 4100; Expected = 90 },
    @{ Mv = 4000; Expected = 80 },
    @{ Mv = 3900; Expected = 70 },
    @{ Mv = 3800; Expected = 60 },
    @{ Mv = 3777; Expected = 57 },
    @{ Mv = 3750; Expected = 50 },
    @{ Mv = 3700; Expected = 40 },
    @{ Mv = 3650; Expected = 30 },
    @{ Mv = 3600; Expected = 20 },
    @{ Mv = 3550; Expected = 10 },
    @{ Mv = 3500; Expected = 0 },
    @{ Mv = 3200; Expected = 0 }
)

foreach ($tc in $tests) {
    $pct = [int]$mVolt.Invoke($null, @([int]$tc.Mv))
    if ($pct -ne $tc.Expected) {
        Fail "ProXVoltageToPercent($($tc.Mv)mV) 计算错误: 实际 $pct, 期望 $($tc.Expected)"
    }
}
Write-Host "PASSED: ADC 报文解析与 15 组放电曲线全值域测试全部断言成功" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [测试 4/4] 官方型号映射与设备分类校验" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$mModel = $t.GetMethod("GetModelName", $bf)
$modelName = $mModel.Invoke($null, @(0x0ABA, "PRO X Wireless"))
if ($modelName -ne "Logitech G PRO X Wireless 游戏耳机") {
    Fail "GetModelName(0x0ABA) 返回错误: $modelName"
}

$mCat = $t.GetMethod("DetectCategory", $bf)
$cat = $mCat.Invoke($null, @(0x0ABA, "Logitech G PRO X Wireless 游戏耳机"))
if ($cat.ToString() -ne "Headset") {
    Fail "DetectCategory 识别错误: $cat (期望 Headset)"
}
Write-Host "PASSED: 官方型号及耳机分类映射完全正确" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host " ALL PASS: 罗技 G PRO X Wireless 游戏耳机适配验证全部通过！" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
exit 0
