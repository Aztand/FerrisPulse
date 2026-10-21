# tests/test_add_device_ai_card.ps1
# 验证：
# 1. 外设添加向导中“自己做自己的开发者”微光卡片与控件层级
# 2. 复制提示词内容规范（包含 AGENT_HANDBOOK、Ferris-echo 官方源，去除冗余词）
# 3. 推荐 AI 工具弹窗（AiToolsDialog）正常实例化，删除冗余标签，链接与 Antigravity 无横杠核验

$ErrorActionPreference = "Stop"

$exePath = "FerrisPulse.exe"
if (-not (Test-Path $exePath)) {
    Write-Host "FAIL: FerrisPulse.exe not found." -ForegroundColor Red
    exit 1
}

# 全内存反射装配，严禁锁定可执行文件句柄
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $exePath).Path)
$assembly = [System.Reflection.Assembly]::Load($bytes)
$tWizard = $assembly.GetType("RazerBatteryTray.AddDeviceWizardForm")
$tAiDlg = $assembly.GetType("RazerBatteryTray.AiToolsDialog")

if ($null -eq $tWizard) {
    Write-Host "FAIL: Cannot find RazerBatteryTray.AddDeviceWizardForm" -ForegroundColor Red
    exit 1
}
if ($null -eq $tAiDlg) {
    Write-Host "FAIL: Cannot find RazerBatteryTray.AiToolsDialog" -ForegroundColor Red
    exit 1
}

Write-Host "--- 测试 1: 验证 AddDeviceWizardForm 提示词内容契约 ---" -ForegroundColor Cyan
$mGetPrompt = $tWizard.GetMethod("GetAiAdaptationPrompt", [System.Reflection.BindingFlags]'Public,Static')
if ($null -eq $mGetPrompt) {
    Write-Host "FAIL: 未找到 GetAiAdaptationPrompt 静态方法！" -ForegroundColor Red
    exit 1
}
$prompt = [string]$mGetPrompt.Invoke($null, $null)

if (-not $prompt.Contains("AGENT_HANDBOOK.md") -or -not $prompt.Contains("AGENT_RULES.md")) {
    Write-Host "FAIL: 提示词未包含第 1 步必读 AGENT_HANDBOOK.md 与 AGENT_RULES.md！" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: 提示词已强制前置 AGENT_HANDBOOK.md 与 AGENT_RULES.md 经验飞轮" -ForegroundColor Green

if (-not $prompt.Contains("https://github.com/Ferris-echo/FerrisPulse.git") -or -not $prompt.Contains("https://gitee.com/Ferris-echo/ferris-pulse.git")) {
    Write-Host "FAIL: 提示词中的仓库地址非官方 Ferris-echo 仓库！" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: 提示词中的 GitHub 与 Gitee 地址已核验为 Ferris-echo 官方源" -ForegroundColor Green

if ($prompt.Contains("国内极速") -or $prompt.Contains("一分钟极速")) {
    Write-Host "FAIL: 提示词中包含不符合调性的词汇！" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: 提示词调性纯净，已剥离所有多余修饰" -ForegroundColor Green

Write-Host "`n--- 测试 2: 验证 AddDeviceWizardForm 窗体与控件装配 ---" -ForegroundColor Cyan
$wizard = [System.Activator]::CreateInstance($tWizard, @($null, [float]1.0))
if ($wizard.ClientSize.Height -lt 550) {
    Write-Host "FAIL: 向导高度不足以容纳 AI 专属卡片，Height=$($wizard.ClientSize.Height)" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: 向导尺寸已适配 AI 开发者卡片 (Height=$($wizard.ClientSize.Height))" -ForegroundColor Green

# 检查私有字段
$fCopy = $tWizard.GetField("btnCopyPrompt", [System.Reflection.BindingFlags]'Instance,NonPublic')
$fTools = $tWizard.GetField("btnAiTools", [System.Reflection.BindingFlags]'Instance,NonPublic')

if ($null -eq $fCopy -or $null -eq $fCopy.GetValue($wizard)) {
    Write-Host "FAIL: 未找到 btnCopyPrompt 复制提示词按钮！" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: btnCopyPrompt 按钮装配正常" -ForegroundColor Green

if ($null -eq $fTools -or $null -eq $fTools.GetValue($wizard)) {
    Write-Host "FAIL: 未找到 btnAiTools 获取工具按钮！" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: btnAiTools 按钮装配正常" -ForegroundColor Green

Write-Host "`n--- 测试 3: 验证 AiToolsDialog 独立弹窗与源码规范（无冗余标签，链接校正） ---" -ForegroundColor Cyan
$aiDlg = [System.Activator]::CreateInstance($tAiDlg, @([float]1.0))
if ($null -eq $aiDlg -or $aiDlg.Controls.Count -lt 4) {
    Write-Host "FAIL: AiToolsDialog 控件不足或创建失败！" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: AiToolsDialog 推荐工具弹窗创建正常 (Controls=$($aiDlg.Controls.Count))" -ForegroundColor Green

# 源码断言
$dlgCs = [System.IO.File]::ReadAllText("src/UI/Forms/AiToolsDialog.cs", [System.Text.Encoding]::UTF8)
if ($dlgCs.Contains("lblTag") -or $dlgCs.Contains("lblVpn")) {
    Write-Host "FAIL: AiToolsDialog 依然包含未删除的标签控件！" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: AiToolsDialog 已成功删除多余杂乱的标签徽章，排版纯净统一" -ForegroundColor Green

if ($dlgCs.Contains("Anti-gravity")) {
    Write-Host "FAIL: Antigravity 中间依然存在多余的一杠！" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: Antigravity 中间已无横杠" -ForegroundColor Green

if (-not $dlgCs.Contains("https://openai.com/zh-Hans-CN/codex/") -or -not $dlgCs.Contains("https://www.deepseek.com/harness/")) {
    Write-Host "FAIL: Codex 或 DeepSeek 链接未更新至指定官网路径！" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: Codex 与 DeepSeek 官网链接校正全部正确" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host " ALL PASS: AI 智能体专属外设适配功能验证全部通过！" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
