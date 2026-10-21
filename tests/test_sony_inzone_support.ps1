# ============================================================================
# 测试脚本: test_sony_inzone_support.ps1
# 目标: 验证索尼 INZONE Buds (WF-G700N) 驱动层契约、BOM / C# 5.0 规范、
#       VID 0x054C / PID 0x0EC2 识别、64 字节报文建帧与校验和、
#       双耳及充电盒独立电量/充电状态解析与回退容灾
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
Write-Host " [测试 1/5] SonyInzoneHelper 源码 BOM 与 C# 5.0 规范核验" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$sonyHelperPath = "$ProjectDir\src\Hardware\SonyInzoneHelper.cs"
Assert-Bom $sonyHelperPath
Assert-CSharp5 $sonyHelperPath
Write-Host "PASSED: SonyInzoneHelper.cs 存在、BOM 正确且完全符合 C# 5.0 铁律" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [测试 2/5] VID:PID 白名单与协议常量核验" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$sonyContent = [System.IO.File]::ReadAllText($sonyHelperPath, [System.Text.Encoding]::UTF8)
foreach ($token in @("0x054C", "0x0EC2", "0xFF04", "0x0001", "0x02", "64", "WF-G700N")) {
    if (-not $sonyContent.Contains($token)) {
        Write-Host "FAILED: SonyInzoneHelper 缺少协议常量或型号声明 $token" -ForegroundColor Red
        exit 1
    }
}
Write-Host "PASSED: 索尼 054C:0EC2、UsagePage 0xFF04、Usage 0x0001、Report 0x02 协议常量完整" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [测试 3/5] 主动电量查询报文建帧与发送校验和断言" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$binPath = "$ProjectDir\FerrisPulse.exe"
if (-not (Test-Path $binPath)) {
    Write-Host "编译二进制以供反射测试..." -ForegroundColor Yellow
    cmd /c "$ProjectDir\build.bat" | Out-Null
}
$asmBytes = [System.IO.File]::ReadAllBytes($binPath)
$asm = [System.Reflection.Assembly]::Load($asmBytes)
$sonyType = $asm.GetType("RazerBatteryTray.SonyInzoneHelper")
if ($null -eq $sonyType) { Write-Host "FAILED: 未找到 SonyInzoneHelper" -ForegroundColor Red; exit 1 }

$buildQuery = $sonyType.GetMethod("BuildQueryPacket", [System.Reflection.BindingFlags]"Public,Static")
[byte[]]$qPkt = $buildQuery.Invoke($null, @([uint16]1))

if ($qPkt.Length -ne 64) { Write-Host "FAILED: 查询包长度非 64 字节 ($($qPkt.Length))" -ForegroundColor Red; exit 1 }
if ($qPkt[0] -ne 0x02 -or $qPkt[1] -ne 0x0C -or $qPkt[6] -ne 0x96 -or $qPkt[7] -ne 0xC3 -or $qPkt[8] -ne 0x41) {
    Write-Host "FAILED: 查询包头魔数异常" -ForegroundColor Red; exit 1
}
if ($qPkt[11] -ne 0x01 -or $qPkt[12] -ne 0x00) {
    Write-Host "FAILED: Sequence 小端字节序异常" -ForegroundColor Red; exit 1
}
# 校验和: (0x96 + 0xC3 + 0x41 + 0x04 + 0x01 + 0x01 + 0x00) & 0xFF = 0x2A0 & 0xFF = 0xA0
if ($qPkt[13] -ne 0xA0) {
    Write-Host "FAILED: 查询包校验和错误 (期望 0xA0, 实际 0x$($qPkt[13].ToString('X2')))" -ForegroundColor Red; exit 1
}
Write-Host "PASSED: 64 字节主动查询报文建帧与校验和算法完全吻合用户真实抓包 (0xA0)" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [测试 4/5] 真实抓包电量报文解析与左右耳/盒状态断言" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$parseResp = $sonyType.GetMethod("ParseBatteryResponse", [System.Reflection.BindingFlags]"Public,Static")
$resolveBatt = $sonyType.GetMethod("ResolvePrimaryBatteryPercent", [System.Reflection.BindingFlags]"Public,Static")
$buildTip = $sonyType.GetMethod("BuildTooltip", [System.Reflection.BindingFlags]"Public,Static")

# 案例 1: 双耳均在耳中 (左耳 100%, 右耳 100%, 充电盒 97%)
# 02 12 04 FF 0F 00 96 C3 14 04 10 01 00 00 64 00 64 FF 61 AA ...
[byte[]]$resp1 = New-Object byte[] 64
$resp1[0] = 0x02; $resp1[1] = 0x12; $resp1[2] = 0x04; $resp1[3] = 0xFF; $resp1[4] = 0x0F; $resp1[5] = 0x00
$resp1[6] = 0x96; $resp1[7] = 0xC3; $resp1[8] = 0x14; $resp1[9] = 0x04; $resp1[10] = 0x10
$resp1[11] = 0x01; $resp1[12] = 0x00
$resp1[13] = 0x00 # L_Stat (未充电)
$resp1[14] = 0x64 # L_Batt (100%)
$resp1[15] = 0x00 # R_Stat (未充电)
$resp1[16] = 0x64 # R_Batt (100%)
$resp1[17] = 0xFF # C_Stat (未充电)
$resp1[18] = 0x61 # C_Batt (97%)
$resp1[19] = 0xAA # Checksum

[object[]]$args1 = @($resp1, $null)
$ok1 = $parseResp.Invoke($null, $args1)
$state1 = $args1[1]

if (-not $ok1 -or $null -eq $state1) { Write-Host "FAILED: 案例 1 报文解析失败" -ForegroundColor Red; exit 1 }
if ($state1.LeftBattery -ne 100 -or $state1.LeftCharging -or
    $state1.RightBattery -ne 100 -or $state1.RightCharging -or
    $state1.CaseBattery -ne 97 -or $state1.CaseCharging -or -not $state1.IsConnected) {
    Write-Host "FAILED: 案例 1 状态解析不符合预期" -ForegroundColor Red; exit 1
}
$pri1 = $resolveBatt.Invoke($null, @($state1))
if ($pri1 -ne 100) { Write-Host "FAILED: 案例 1 主电量期望 100, 实际 $pri1" -ForegroundColor Red; exit 1 }
$tip1 = $buildTip.Invoke($null, @($state1))
if ($tip1 -ne "左耳: 100% | 右耳: 100% | 充电盒: 97%") {
    Write-Host "FAILED: 案例 1 提示文本不符: $tip1" -ForegroundColor Red; exit 1
}
Write-Host "PASSED: 案例 1 双耳在线 (100%/100%/97%) 解析与 Tooltip 完美匹配" -ForegroundColor Green

# 案例 2: 左耳在盒内 (0xFF), 右耳在耳中 (100%), 充电盒 97%
# 02 12 04 FF 0F 00 96 C3 14 04 10 01 00 00 FF 00 64 FF 61 45 ...
[byte[]]$resp2 = New-Object byte[] 64
[System.Array]::Copy($resp1, $resp2, 64)
$resp2[14] = 0xFF # 左耳在盒内
$resp2[19] = 0x45 # 校验和

[object[]]$args2 = @($resp2, $null)
$ok2 = $parseResp.Invoke($null, $args2)
$state2 = $args2[1]

if (-not $ok2 -or $state2.LeftBattery -ne -1 -or $state2.RightBattery -ne 100 -or $state2.CaseBattery -ne 97) {
    Write-Host "FAILED: 案例 2 单耳在盒解析异常 (L=$($state2.LeftBattery), R=$($state2.RightBattery))" -ForegroundColor Red; exit 1
}
$pri2 = $resolveBatt.Invoke($null, @($state2))
if ($pri2 -ne 100) { Write-Host "FAILED: 案例 2 主电量取右耳 100% 失败, 实际 $pri2" -ForegroundColor Red; exit 1 }
$tip2 = $buildTip.Invoke($null, @($state2))
if ($tip2 -ne "右耳: 100% | 充电盒: 97%") {
    Write-Host "FAILED: 案例 2 提示文本不符: $tip2" -ForegroundColor Red; exit 1
}
Write-Host "PASSED: 案例 2 单耳在盒 (0xFF) 自动隐藏并选取在耳单耳电量" -ForegroundColor Green

# 案例 3: 充电状态检测
[byte[]]$resp3 = New-Object byte[] 64
[System.Array]::Copy($resp1, $resp3, 64)
$resp3[13] = 0x01 # 左耳充电
$resp3[17] = 0x01 # 充电盒充电
$resp3[19] = 0xAD # 校验和: (0x96+0xC3+0x14+0x04+0x10+0x01+0x00+0x01+0x64+0x00+0x64+0x01+0x61) & 0xFF = 0xAD

[object[]]$args3 = @($resp3, $null)
$ok3 = $parseResp.Invoke($null, $args3)
$state3 = $args3[1]
if (-not $ok3 -or -not $state3.LeftCharging -or $state3.RightCharging -or -not $state3.CaseCharging) {
    Write-Host "FAILED: 案例 3 充电状态检测异常" -ForegroundColor Red; exit 1
}
$tip3 = $buildTip.Invoke($null, @($state3))
if (-not $tip3.Contains("左耳: 100%⚡") -or -not $tip3.Contains("充电盒: 97%⚡")) {
    Write-Host "FAILED: 案例 3 充电闪电符号展示异常: $tip3" -ForegroundColor Red; exit 1
}
Write-Host "PASSED: 案例 3 独立充电状态 (Left / Case) 闪电标记完全正确" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [测试 5/5] 校验和篡改与非法报文防崩溃容灾断言" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

[byte[]]$badResp = New-Object byte[] 64
[System.Array]::Copy($resp1, $badResp, 64)
$badResp[19] = 0x00 # 故意篡改校验和

[object[]]$argsBad = @($badResp, $null)
$okBad = $parseResp.Invoke($null, $argsBad)
if ($okBad) {
    Write-Host "FAILED: 篡改校验和后仍被判定合法" -ForegroundColor Red
    exit 1
}
Write-Host "PASSED: 校验和不匹配时严格拒绝，杜绝脏数据干扰" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host " ALL 5/5 SONY INZONE BUDS TESTS PASSED! (索尼入耳式耳机驱动层契约测试全量通过)" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
