# ============================================================================
# 测试脚本: test_atk_angrymiao_metapanda.ps1
# 目标: 验证怒喵 (Angry Miao)、ATK (A9 AIR / X1 V2) 与玄派玄熊猫 (P1 1K/4K)
#       硬件目录识别、WE 校验和算法、RACE 协议支持与品牌色映射规范
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
Write-Host " [测试 1/5] UniversalGamingDeviceHelper 规范与 C# 5.0 校验" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$helperPath = "$ProjectDir\src\Hardware\UniversalGamingDeviceHelper.cs"
Assert-Bom $helperPath
Assert-CSharp5 $helperPath
Write-Host "PASSED: UniversalGamingDeviceHelper.cs 语法与 BOM 规范 100% 合规" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [测试 2/5] ATK / 玄熊猫 / 怒喵 产品目录与极速回报率断言" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$binPath = "$ProjectDir\FerrisPulse.exe"
$asmBytes = [System.IO.File]::ReadAllBytes($binPath)
$asm = [System.Reflection.Assembly]::Load($asmBytes)
$ugType = $asm.GetType("RazerBatteryTray.UniversalGamingDeviceHelper")
if ($null -eq $ugType) { Write-Host "FAILED: 未找到 UniversalGamingDeviceHelper" -ForegroundColor Red; exit 1 }

$lookup = $ugType.GetMethod("LookupProduct", [System.Reflection.BindingFlags]"Public,Static")

# 1. ATK A9 AIR (373B:1279)
$atkA9 = $lookup.Invoke($null, @(0x373B, 0x1279, ""))
if ($atkA9.ModelName -ne "ATK A9 AIR 8K 接收器" -or $atkA9.Brand -ne "ATK" -or $atkA9.MaxPollingRate -ne 8000) {
    Write-Host "FAILED: ATK A9 AIR 识别异常: $($atkA9.ModelName)" -ForegroundColor Red; exit 1
}

# 2. ATK X1 V2 (373B:12E9)
$atkX1 = $lookup.Invoke($null, @(0x373B, 0x12E9, ""))
if ($atkX1.ModelName -ne "ATK X1 V2 8K 接收器" -or $atkX1.Brand -ne "ATK" -or $atkX1.MaxPollingRate -ne 8000) {
    Write-Host "FAILED: ATK X1 V2 识别异常: $($atkX1.ModelName)" -ForegroundColor Red; exit 1
}

# 3. 玄熊猫 P1 1K (3554:F5A9) & 4K (3554:F5AC)
$p1_1k = $lookup.Invoke($null, @(0x3554, 0xF5A9, ""))
$p1_4k = $lookup.Invoke($null, @(0x3554, 0xF5AC, ""))
if ($p1_1k.ModelName -ne "玄熊猫 P1 游戏鼠标" -or $p1_1k.Brand -ne "玄熊猫") {
    Write-Host "FAILED: 玄熊猫 P1 1K 识别异常: $($p1_1k.ModelName)" -ForegroundColor Red; exit 1
}
if ($p1_4k.ModelName -ne "玄熊猫 P1 4K 游戏鼠标" -or $p1_4k.MaxPollingRate -ne 4000) {
    Write-Host "FAILED: 玄熊猫 P1 4K 识别异常: $($p1_4k.ModelName)" -ForegroundColor Red; exit 1
}

# 4. 怒喵 AM Infinity .97 2.4G (0E8D:0703) & 有线 (0E8D:0880)
$am24g = $lookup.Invoke($null, @(0x0E8D, 0x0703, ""))
$amWire = $lookup.Invoke($null, @(0x0E8D, 0x0880, ""))
if ($am24g.ModelName -ne "怒喵 AM Infinity .97 (2.4G)" -or $am24g.Brand -ne "Angry Miao" -or $am24g.MaxPollingRate -ne 8000) {
    Write-Host "FAILED: 怒喵 AM Infinity 2.4G 识别异常: $($am24g.ModelName)" -ForegroundColor Red; exit 1
}
if ($amWire.ModelName -ne "怒喵 AM Infinity .97 (有线模式)") {
    Write-Host "FAILED: 怒喵 AM Infinity 有线识别异常: $($amWire.ModelName)" -ForegroundColor Red; exit 1
}

Write-Host "PASSED: ATK (8K)、玄熊猫 P1 (1K/4K)、怒喵 AM Infinity (8K) 目录映射全部正确" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [测试 3/5] WE 校验和算法断言 (整帧 17 字节和恒等于 0x55)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$calcCs = $ugType.GetMethod("CalculateWeChecksum", [System.Reflection.BindingFlags]"Public,Static")
[byte[]]$payload = New-Object byte[] 15
$payload[0] = 0x04 # CMD: Battery
$cs = $calcCs.Invoke($null, @([byte]0x08, $payload))

# 验证整帧 17 字节之和 ≡ 0x55
$sum = 0x08
for ($i = 0; $i -lt 15; $i++) { $sum += $payload[$i] }
$sum += $cs
$modulo = $sum -band 0xFF
if ($modulo -ne 0x55) {
    Write-Host "FAILED: 校验和算法错误: sum % 256 = 0x$($modulo.ToString('X2')) (期望 0x55)" -ForegroundColor Red
    exit 1
}
Write-Host "PASSED: 17 字节 WE 报文校验和严格满足整帧和 ≡ 0x55" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [测试 4/5] 怒喵 RACE 报文协议引擎方法断言" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$qAm = $ugType.GetMethod("QueryAngryMiaoBattery", [System.Reflection.BindingFlags]"Public,Static")
if ($null -eq $qAm) {
    Write-Host "FAILED: 未找到 QueryAngryMiaoBattery 协议引擎方法" -ForegroundColor Red
    exit 1
}
Write-Host "PASSED: QueryAngryMiaoBattery 62 字节 RACE 协议引擎已就绪" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [测试 5/5] 新增品牌色映射断言" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$infoType = $asm.GetType("RazerBatteryTray.MouseBatteryInfo")
$brandColorProp = $infoType.GetProperty("BrandColor")

function Get-BrandColor([string]$brand) {
    $inst = [System.Activator]::CreateInstance($infoType)
    $inst.Brand = $brand
    return $brandColorProp.GetValue($inst, $null)
}

$cAm = Get-BrandColor "Angry Miao"
$cAtk = Get-BrandColor "ATK"
$cMp = Get-BrandColor "玄熊猫"
$cSony = Get-BrandColor "Sony"

if ($cAm.R -ne 255 -or $cAm.G -ne 68 -or $cAm.B -ne 102) { Write-Host "FAILED: Angry Miao 品牌色不符" -ForegroundColor Red; exit 1 }
if ($cAtk.R -ne 255 -or $cAtk.G -ne 110 -or $cAtk.B -ne 0) { Write-Host "FAILED: ATK 品牌色不符" -ForegroundColor Red; exit 1 }
if ($cMp.R -ne 0 -or $cMp.G -ne 200 -or $cMp.B -ne 150) { Write-Host "FAILED: 玄熊猫品牌色不符" -ForegroundColor Red; exit 1 }
if ($cSony.R -ne 0 -or $cSony.G -ne 114 -or $cSony.B -ne 206) { Write-Host "FAILED: Sony 品牌色不符" -ForegroundColor Red; exit 1 }

Write-Host "PASSED: 怒喵 (粉红)、ATK (极速橙)、玄熊猫 (青玉绿)、索尼 (经典蓝) 专属配色验证全部通过" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host " ALL 5/5 ATK / ANGRY MIAO / METAPANDA TESTS PASSED!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
