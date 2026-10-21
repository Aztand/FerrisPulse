# tests/test_game_opt_osd_layout.ps1
# 本测试验证全屏游戏优化双开 OSD 卡片的排版美化与视觉规范：
# 1. 顶部标题样式参考单独回报率切换样式（无 Emoji，色泽沉稳，居中规范）
# 2. DPI 和回报率数值字体放大（标准 DPI 18.5pt，独立 XY 13.5pt，回报率 18.5pt）
# 3. 底部战术胶囊徽章不含“第几档”，仅展示纯净状态（极速超低延迟已激活 / 桌面节能平稳模式）
# 4. 卡片窗体尺寸适度拓宽为 248x76，居中留白对称优美

$ErrorActionPreference = "Stop"

$exePath = "FerrisPulse.exe"
if (-not (Test-Path $exePath)) {
    Write-Host "FAIL: FerrisPulse.exe not found." -ForegroundColor Red
    exit 1
}

# 全内存反射装配，严禁锁定可执行文件句柄
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $exePath).Path)
$assembly = [System.Reflection.Assembly]::Load($bytes)
$tOsd = $assembly.GetType("RazerBatteryTray.DpiOsdForm")

if ($null -eq $tOsd) {
    Write-Host "FAIL: Cannot find RazerBatteryTray.DpiOsdForm" -ForegroundColor Red
    exit 1
}

$osd = [System.Activator]::CreateInstance($tOsd)

# 辅助函数：通过反射读取私有字段
function Get-OsdField($name) {
    $f = $tOsd.GetField($name, [System.Reflection.BindingFlags]'Instance,NonPublic')
    if ($null -ne $f) {
        return $f.GetValue($osd)
    }
    return $null
}

Write-Host "--- 测试 1: 验证 ShowGameOptimization 激活后尺寸与状态 ---" -ForegroundColor Cyan
$osd.ShowGameOptimization($true, $true, 3000, 2250, 4, 5, $true, 4000, "Razer")

$isDual = Get-OsdField "isDualOptimizationMode"
if (-not $isDual) {
    Write-Host "FAIL: ShowGameOptimization 未激活 isDualOptimizationMode！" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: 成功激活 isDualOptimizationMode" -ForegroundColor Green

# 验证窗体宽度与高度
if ($osd.Width -lt 240 -or $osd.Height -lt 74) {
    Write-Host "FAIL: OSD 尺寸过小，当前 Size: $($osd.Size)" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: OSD 窗体尺寸适度拓宽充足: $($osd.Size.Width)x$($osd.Size.Height)" -ForegroundColor Green

Write-Host "`n--- 测试 2: 验证源码排版规范断言（无 Emoji、无'第几档'） ---" -ForegroundColor Cyan
$csPath = "src/UI/Forms/DpiOsdForm.cs"
$csContent = [System.IO.File]::ReadAllText($csPath, [System.Text.Encoding]::UTF8)

# 1. 验证不含损坏的 Emoji
if ($csContent.Contains("⚡ 全屏电竞性能优化") -or $csContent.Contains("🍃 常规桌面状态恢复")) {
    Write-Host "FAIL: 源码中依然包含未剥离的 Emoji 字符！" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: 成功去除 Emoji，使用现代纯净标题排版" -ForegroundColor Green

# 2. 验证底部徽章不包含“第几档”
if ($csContent.Contains("第 {0} 档 · 极速超低延迟已激活") -or $csContent.Contains("第 {0} 档 · 桌面节能平稳模式")) {
    Write-Host "FAIL: 底部战术徽章依然包含'第几档'！" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: 底部战术徽章彻底移除了'第几档'前缀，纯净利落" -ForegroundColor Green

# 3. 验证数值字体放大
if (-not $csContent.Contains("18.5f * dpiScale") -or -not $csContent.Contains("13.5f : 18.5f")) {
    Write-Host "FAIL: 未检测到 DPI / 回报率数值放大至 18.5pt / 13.5pt！" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: DPI 与回报率字号成功放大至 18.5pt / 13.5pt 高可读性规范" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host " ALL PASS: 双开游戏优化 OSD 排版美化与排版断言全部通过！" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
