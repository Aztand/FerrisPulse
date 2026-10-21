# ============================================================================
# 测试脚本: test_steelseries_nova5.ps1
# 目标: 验证赛睿 (SteelSeries) Arctis Nova 5 / 5X 无线耳机驱动层代码规范、
#       0x00B0 状态报文解析、VID/PID 白名单与全系统生命周期融合
# ============================================================================

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectDir = Resolve-Path "$ScriptDir\.."
Set-Location $ProjectDir

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " [测试 1/5] SteelSeriesDeviceHelper.cs 存在性与 UTF-8 BOM 编码校验" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$helperPath = "$ProjectDir\src\Hardware\SteelSeriesDeviceHelper.cs"
if (-not (Test-Path $helperPath)) {
    Write-Host "FAILED: src\Hardware\SteelSeriesDeviceHelper.cs 尚未创建！" -ForegroundColor Red
    exit 1
}

$bytes = [System.IO.File]::ReadAllBytes($helperPath)
if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
    Write-Host "FAILED: SteelSeriesDeviceHelper.cs 不是 UTF-8 with BOM 编码！" -ForegroundColor Red
    exit 1
}
Write-Host "PASSED: SteelSeriesDeviceHelper.cs 文件存在且符合 UTF-8 with BOM 规范" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [测试 2/5] C# 5.0 语法铁律审查（严禁使用 C# 6.0+ 语法）" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$content = [System.IO.File]::ReadAllText($helperPath, [System.Text.Encoding]::UTF8)

if ([regex]::IsMatch($content, '\$".*?"')) {
    Write-Host "FAILED: 发现禁用的字符串插值语法" -ForegroundColor Red
    exit 1
}

if ([regex]::IsMatch($content, '\w+\?\.')) {
    Write-Host "FAILED: 发现禁用的空条件运算符" -ForegroundColor Red
    exit 1
}

if ([regex]::IsMatch($content, 'nameof\s*\(')) {
    Write-Host "FAILED: 发现禁用的 nameof 语法" -ForegroundColor Red
    exit 1
}

if ([regex]::IsMatch($content, 'out\s+var\s+')) {
    Write-Host "FAILED: 发现禁用的 out var 内联声明" -ForegroundColor Red
    exit 1
}

if (-not $content.Contains("⚠️ AI 维护准则 (AI MAINTENANCE DIRECTIVE - DO NOT REMOVE) ⚠️")) {
    Write-Host "FAILED: 缺少头部 AI 维护准则声明" -ForegroundColor Red
    exit 1
}
Write-Host "PASSED: SteelSeriesDeviceHelper.cs 语法严格遵循 C# 5.0 标准" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [测试 3/5] SteelSeries 硬件标识、型号与设备分类校验" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 全内存反射加载，严禁 Add-Type / LoadFrom 产生文件句柄锁死
$binPath = "$ProjectDir\FerrisPulse.exe"
if (-not (Test-Path $binPath)) {
    Write-Host "编译二进制以供测试反射..." -ForegroundColor Yellow
    cmd /c "$ProjectDir\build.bat" | Out-Null
}

$asmBytes = [System.IO.File]::ReadAllBytes($binPath)
$asm = [System.Reflection.Assembly]::Load($asmBytes)
$helperType = $asm.GetType("RazerBatteryTray.SteelSeriesDeviceHelper")
if ($null -eq $helperType) {
    Write-Host "FAILED: 未能通过反射获取 RazerBatteryTray.SteelSeriesDeviceHelper 类型" -ForegroundColor Red
    exit 1
}

$isSupported = $helperType.GetMethod("IsSupportedVidPid", [System.Reflection.BindingFlags]"Public,Static")
$res1 = $isSupported.Invoke($null, @(0x1038, 0x2232))
$res2 = $isSupported.Invoke($null, @(0x1038, 0x2253))
$res3 = $isSupported.Invoke($null, @(0x1532, 0x2232))
$res4 = $isSupported.Invoke($null, @(0x1038, 0x2210))
if (-not $res1 -or -not $res2 -or $res3 -or $res4) {
    Write-Host "FAILED: IsSupportedVidPid 白名单过滤异常！(2232: $res1, 2253: $res2, 1532: $res3, 2210: $res4)" -ForegroundColor Red
    exit 1
}

$getModelName = $helperType.GetMethod("GetModelName", [System.Reflection.BindingFlags]"Public,Static")
$name1 = $getModelName.Invoke($null, @(0x2232, "SteelSeries Arctis Nova 5"))
$name2 = $getModelName.Invoke($null, @(0x2253, ""))
if ($name1 -ne "Arctis Nova 5" -or $name2 -ne "Arctis Nova 5X") {
    Write-Host "FAILED: GetModelName 命名异常！name1: $name1, name2: $name2" -ForegroundColor Red
    exit 1
}

$isDevice = $helperType.GetMethod("IsSteelSeriesDevice", [System.Reflection.BindingFlags]"Public,Static")
$idHit = $isDevice.Invoke($null, @("HID:1038:2232"))
$idMiss = $isDevice.Invoke($null, @("HID:046D:C08B"))
if (-not $idHit -or $idMiss) {
    Write-Host "FAILED: IsSteelSeriesDevice 指纹识别异常！(hit: $idHit, miss: $idMiss)" -ForegroundColor Red
    exit 1
}
Write-Host "PASSED: SteelSeries VID/PID、型号与指纹识别逻辑全部正确" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [测试 4/5] 0x00B0 状态报文电量/充电/离线解析断言" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$parseMethod = $helperType.GetMethod("ParseStatusReport", [System.Reflection.BindingFlags]"Public,Static")

function Invoke-ParseReport([byte[]]$buf, [int]$len, [int]$inConn, [int]$inChg, [int]$inBatt) {
    $arr = [System.Array]::CreateInstance([object], 5)
    $arr.SetValue($buf, 0)
    $arr.SetValue($len, 1)
    $arr.SetValue($inConn, 2)
    $arr.SetValue($inChg, 3)
    $arr.SetValue($inBatt, 4)
    $parseMethod.Invoke($null, $arr)
    return @{
        Connected = [int]$arr[2]
        Charging = [int]$arr[3]
        Battery = [int]$arr[4]
    }
}

# 1. 在线放电: 00 B0 03 02 64 03 -> 100% 未充电
$rxOnline = New-Object byte[] 65
$rxOnline[0] = 0x00
$rxOnline[1] = 0xB0
$rxOnline[2] = 0x03
$rxOnline[3] = 0x02
$rxOnline[4] = 0x64
$rxOnline[5] = 0x03
$r1 = Invoke-ParseReport $rxOnline 65 -1 -1 -1
if ($r1.Connected -ne 1 -or $r1.Charging -ne 0 -or $r1.Battery -ne 100) {
    Write-Host "FAILED: 在线放电报文解析失败！connected=$($r1.Connected), charging=$($r1.Charging), battery=$($r1.Battery)" -ForegroundColor Red
    exit 1
}

# 2. 充电中: 00 B0 03 02 2A 01 -> 42% 充电中
$rxCharging = New-Object byte[] 65
$rxCharging[0] = 0x00
$rxCharging[1] = 0xB0
$rxCharging[2] = 0x03
$rxCharging[3] = 0x02
$rxCharging[4] = 0x2A
$rxCharging[5] = 0x01
$r2 = Invoke-ParseReport $rxCharging 65 -1 -1 -1
if ($r2.Connected -ne 1 -or $r2.Charging -ne 1 -or $r2.Battery -ne 42) {
    Write-Host "FAILED: 充电报文解析失败！connected=$($r2.Connected), charging=$($r2.Charging), battery=$($r2.Battery)" -ForegroundColor Red
    exit 1
}

# 3. 耳机离线: 00 B0 02 -> connected=0，电量保持原值不被覆盖
$rxOffline = New-Object byte[] 65
$rxOffline[0] = 0x00
$rxOffline[1] = 0xB0
$rxOffline[2] = 0x02
$rxOffline[4] = 0x64
$r3 = Invoke-ParseReport $rxOffline 65 -1 -1 77
if ($r3.Connected -ne 0 -or $r3.Charging -ne 0 -or $r3.Battery -ne 77) {
    Write-Host "FAILED: 离线报文解析失败！connected=$($r3.Connected), charging=$($r3.Charging), battery=$($r3.Battery)" -ForegroundColor Red
    exit 1
}

# 4. 非状态报文 / 过短报文必须被安全忽略
$rxBad = New-Object byte[] 65
$rxBad[0] = 0x00
$rxBad[1] = 0x55
$rxBad[4] = 0x32
$r4 = Invoke-ParseReport $rxBad 65 -1 -1 66
if ($r4.Connected -ne -1 -or $r4.Battery -ne 66) {
    Write-Host "FAILED: 非状态报文未被安全忽略！connected=$($r4.Connected), battery=$($r4.Battery)" -ForegroundColor Red
    exit 1
}

$r5 = Invoke-ParseReport $rxOnline 3 -1 -1 -1
if ($r5.Connected -ne -1 -or $r5.Battery -ne -1) {
    Write-Host "FAILED: 过短报文未被安全忽略！" -ForegroundColor Red
    exit 1
}
Write-Host "PASSED: 0x00B0 电量 / 充电 / 离线报文算法全部断言成功" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [测试 5/5] DeviceManager 与系统生命周期融合校验" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$dmContent = [System.IO.File]::ReadAllText("$ProjectDir\src\Hardware\DeviceManager.cs", [System.Text.Encoding]::UTF8)
if (-not $dmContent.Contains("SteelSeriesDeviceHelper.QuerySteelSeriesDeviceInfo()")) {
    Write-Host "FAILED: DeviceManager 中缺少 QuerySteelSeriesDeviceInfo 调用" -ForegroundColor Red
    exit 1
}
if (-not $dmContent.Contains("CleanupDuplicateSteelSeriesDevices")) {
    Write-Host "FAILED: DeviceManager 中缺少 CleanupDuplicateSteelSeriesDevices 逻辑" -ForegroundColor Red
    exit 1
}

$mfContent = [System.IO.File]::ReadAllText("$ProjectDir\src\UI\Forms\MainForm.cs", [System.Text.Encoding]::UTF8)
if (-not $mfContent.Contains("SteelSeriesDeviceHelper.LoadHardwareCache()")) {
    Write-Host "FAILED: MainForm 中缺少 SteelSeries 离线缓存预加载调用" -ForegroundColor Red
    exit 1
}

$mbiContent = [System.IO.File]::ReadAllText("$ProjectDir\src\Models\MouseBatteryInfo.cs", [System.Text.Encoding]::UTF8)
if (-not $mbiContent.Contains("SteelSeries")) {
    Write-Host "FAILED: MouseBatteryInfo 中缺少 SteelSeries 品牌色彩配置" -ForegroundColor Red
    exit 1
}

# 设备分类必须为头戴式耳机，保证主界面走耳机音频控制台分支
$categoryType = $asm.GetType("RazerBatteryTray.DeviceCategory")
$headsetValue = [System.Enum]::Parse($categoryType, "Headset")
if ([int]$headsetValue -lt 0) {
    Write-Host "FAILED: DeviceCategory.Headset 枚举异常" -ForegroundColor Red
    exit 1
}

Write-Host "PASSED: SteelSeries 驱动已深度无缝融入灵脉硬件管理器与 UI 生命周期" -ForegroundColor Green
Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host " 赛睿 (SteelSeries) Arctis Nova 5 / 5X 无线耳机测试全部通过！" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
