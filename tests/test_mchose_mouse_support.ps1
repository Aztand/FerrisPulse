# ============================================================================
# 测试脚本: test_mchose_mouse_support.ps1
# 目标: 验证迈从 (MCHOSE) A5 V2 Ultra 鼠标私有 HID 驱动规范：
#       0x11/0x06 身份与电量逆向解析、0x12/0x67 XY轴独立DPI配置、
#       125Hz~8000Hz 超高回报率档位与通用协议物理隔离。
# ============================================================================

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectDir = Resolve-Path "$ScriptDir\.."
Set-Location $ProjectDir

function Assert-Bom([string]$path) {
    if (-not (Test-Path $path)) {
        Write-Host "FAILED: 文件不存在: $path" -ForegroundColor Red
        exit 1
    }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
        Write-Host "FAILED: 文件不是 UTF-8 with BOM: $path" -ForegroundColor Red
        exit 1
    }
}

function Assert-CSharp5([string]$path) {
    $content = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    if ([regex]::IsMatch($content, '\$".*?"')) { Write-Host "FAILED: 字符串插值: $path" -ForegroundColor Red; exit 1 }
    if ([regex]::IsMatch($content, '\w+\?\.')) { Write-Host "FAILED: 空条件运算符: $path" -ForegroundColor Red; exit 1 }
    if ([regex]::IsMatch($content, 'nameof\s*\(')) { Write-Host "FAILED: nameof: $path" -ForegroundColor Red; exit 1 }
    if ([regex]::IsMatch($content, 'out\s+var\s+')) { Write-Host "FAILED: out var: $path" -ForegroundColor Red; exit 1 }
    if (-not $content.Contains("⚠️ AI 维护准则 (AI MAINTENANCE DIRECTIVE - DO NOT REMOVE) ⚠️")) {
        Write-Host "FAILED: 缺少 AI 维护准则声明: $path" -ForegroundColor Red; exit 1
    }
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " [测试 1/5] 迈从鼠标驱动文件编码与 C# 5.0 规范" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$helperPath = "$ProjectDir\src\Hardware\MchoseMouseHelper.cs"
Assert-Bom $helperPath
Assert-CSharp5 $helperPath

Write-Host "PASSED: MchoseMouseHelper.cs 规范健全、BOM 完整且符合 C# 5.0 铁律" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [测试 2/5] 全内存反射加载与类型契约验证" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$binPath = "$ProjectDir\FerrisPulse.exe"
if (-not (Test-Path $binPath)) {
    Write-Host "重新编译以供测试..." -ForegroundColor Yellow
    cmd /c "$ProjectDir\build.bat" | Out-Null
}

$asmBytes = [System.IO.File]::ReadAllBytes($binPath)
$asm = [System.Reflection.Assembly]::Load($asmBytes)
$mchType = $asm.GetType("RazerBatteryTray.MchoseMouseHelper")
if ($null -eq $mchType) {
    Write-Host "FAILED: 程序集中未找到 RazerBatteryTray.MchoseMouseHelper" -ForegroundColor Red
    exit 1
}

$methods = @("TryParseIdentityResponse", "ParseConfigPayload", "GetSupportedPollingRatesForMode", "GetModelName", "QueryAllMchoseMice")
foreach ($m in $methods) {
    $mi = $mchType.GetMethod($m, [System.Reflection.BindingFlags]"Public,Static")
    if ($null -eq $mi) {
        Write-Host "FAILED: 缺少公共静态方法 $m" -ForegroundColor Red
        exit 1
    }
}
Write-Host "PASSED: MchoseMouseHelper 核心契约方法全部就绪" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [测试 3/5] 0x11/0xF9 异或身份与物理电量应答解析断言" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$tryParseIdentity = $mchType.GetMethod("TryParseIdentityResponse", [System.Reflection.BindingFlags]"Public,Static")

[byte[]]$resp = New-Object byte[] 20
$resp[0] = 0x11
$resp[1] = 0xF9
$resp[2] = [byte](0x37 -bxor 0xFF)
$resp[3] = [byte](0x38 -bxor 0xFF)
$resp[4] = [byte](0x0C -bxor 0xFF)
$resp[5] = [byte](0x10 -bxor 0xFF)
$resp[10] = [byte](0x09 -bxor 0xFF)
$resp[11] = [byte](76 -bxor 0xFF)
$resp[12] = [byte](1 -bxor 0xFF)

[object[]]$pArgs = New-Object object[] 6
$pArgs[0] = $resp
$pArgs[1] = 0
$pArgs[2] = 0
$pArgs[3] = 0
$pArgs[4] = 0
$pArgs[5] = 0

$ok = $tryParseIdentity.Invoke($null, $pArgs)
if (-not $ok) { Write-Host "FAILED: 正常 0x11/0xF9 身份报文未能成功解析" -ForegroundColor Red; exit 1 }

$parsedVid = [int]$pArgs[1]
$parsedPid = [int]$pArgs[2]
$parsedFlags = [int]$pArgs[3]
$parsedBattery = [int]$pArgs[4]
$parsedCharge = [int]$pArgs[5]

if ($parsedVid -ne 0x3837 -or $parsedPid -ne 0x100C -or $parsedBattery -ne 76 -or $parsedCharge -ne 1) {
    Write-Host "FAILED: 身份报文解析字段不匹配: VID=$parsedVid, PID=$parsedPid, Bat=$parsedBattery, Chg=$parsedCharge" -ForegroundColor Red
    exit 1
}

$resp[1] = 0x00
$badOk = $tryParseIdentity.Invoke($null, $pArgs)
if ($badOk) { Write-Host "FAILED: 状态码非 0xF9 时应返回 false" -ForegroundColor Red; exit 1 }

Write-Host "PASSED: 0x11/0xF9 异或反转报文解析完美，电量 76% 与充电状态精确解析" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [测试 4/5] 0x12/0x67 XY 轴独立 DPI 配置与回报率档位解析" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$parseConfig = $mchType.GetMethod("ParseConfigPayload", [System.Reflection.BindingFlags]"Public,Static")

[byte[]]$payload = New-Object byte[] 63
$payload[1] = [byte]((0x02 -shl 4) -bor 0x01)
$payload[2] = [byte]((0x04 -shl 4) -bor 0x02)
$payload[16] = [byte]5

$payload[4 + 1 * 2] = [byte](1600 -band 0xFF)
$payload[5 + 1 * 2] = [byte]((1600 -shr 8) -band 0xFF)
$payload[51 + 1 * 2] = [byte](1200 -band 0xFF)
$payload[52 + 1 * 2] = [byte]((1200 -shr 8) -band 0xFF)

[object[]]$cfgArgs = New-Object object[] 1
$cfgArgs[0] = $payload
$cfgObj = $parseConfig.Invoke($null, $cfgArgs)
if ($null -eq $cfgObj) { Write-Host "FAILED: 配置 payload 解析失败" -ForegroundColor Red; exit 1 }

$dpiX1 = $cfgObj.DpiX[1]
$dpiY1 = $cfgObj.DpiY[1]
$wiredRateIdx = $cfgObj.WiredRateIndex
$wirelessRateIdx = $cfgObj.WirelessRateIndex

if ($dpiX1 -ne 1600 -or $dpiY1 -ne 1200 -or $wiredRateIdx -ne 2 -or $wirelessRateIdx -ne 4) {
    Write-Host "FAILED: DPI 配置解析错误: X=$dpiX1, Y=$dpiY1, WiredRate=$wiredRateIdx, WirelessRate=$wirelessRateIdx" -ForegroundColor Red
    exit 1
}

$getRates = $mchType.GetMethod("GetSupportedPollingRatesForMode", [System.Reflection.BindingFlags]"Public,Static")
[object[]]$rArgs0 = New-Object object[] 1
$rArgs0[0] = 0
$wiredRates = $getRates.Invoke($null, $rArgs0)

[object[]]$rArgs1 = New-Object object[] 1
$rArgs1[0] = 1
$wirelessRates = $getRates.Invoke($null, $rArgs1)

if ($wiredRates.Length -ne 5 -or $wiredRates[4] -ne 8000) {
    Write-Host "FAILED: 有线模式最高应为 8000Hz" -ForegroundColor Red; exit 1
}
if ($wirelessRates.Length -ne 5 -or $wirelessRates[4] -ne 4000) {
    Write-Host "FAILED: 2.4G 无线最高应为 4000Hz" -ForegroundColor Red; exit 1
}

Write-Host "PASSED: XY 轴独立 DPI (1600x1200) 与 8K 有线/4K 无线回报率解析完全正确" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [测试 5/5] 通用电竞协议与迈从键盘双重物理隔离" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$ugType = $asm.GetType("RazerBatteryTray.UniversalGamingDeviceHelper")
$isSupportedGaming = $ugType.GetMethod("IsSupportedGamingDevice", [System.Reflection.BindingFlags]"Public,Static")

[object[]]$ugArgs1 = New-Object object[] 3
$ugArgs1[0] = 0x3837
$ugArgs1[1] = "hid#vid_3837_pid_100c"
$ugArgs1[2] = "MCHOSE A5"
$isGamingMchose = $isSupportedGaming.Invoke($null, $ugArgs1)

[object[]]$ugArgs2 = New-Object object[] 3
$ugArgs2[0] = 0x5253
$ugArgs2[1] = "hid#vid_5253_pid_1101"
$ugArgs2[2] = "MCHOSE A5"
$isGamingMchoseAlt = $isSupportedGaming.Invoke($null, $ugArgs2)

if ($isGamingMchose -or $isGamingMchoseAlt) {
    Write-Host "FAILED: UniversalGamingDeviceHelper 未对 MCHOSE 进行物理隔离" -ForegroundColor Red
    exit 1
}

$kbType = $asm.GetType("RazerBatteryTray.MchoseDeviceHelper")
$isKb = $kbType.GetMethod("IsSupportedVidPid", [System.Reflection.BindingFlags]"Public,Static")

[object[]]$kbArgs = New-Object object[] 2
$kbArgs[0] = 0x3837
$kbArgs[1] = 0x3033
$kbCheck = $isKb.Invoke($null, $kbArgs)

[object[]]$mouseArgs = New-Object object[] 2
$mouseArgs[0] = 0x3837
$mouseArgs[1] = 0x100C
$mouseCheck = $isKb.Invoke($null, $mouseArgs)

if (-not $kbCheck -or $mouseCheck) {
    Write-Host "FAILED: 键盘与鼠标在 MchoseDeviceHelper 中未实现正确隔离" -ForegroundColor Red
    exit 1
}

Write-Host "PASSED: 迈从鼠标、迈从键盘与通用电竞协议三方物理隔离彻底有效！" -ForegroundColor Green
Write-Host "`n>>> 全部 5 项迈从 A5 V2 鼠标自动化契约测试 100% 通过！ <<<" -ForegroundColor Green
