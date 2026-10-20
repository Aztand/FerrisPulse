# 📘 FerrisPulse · 灵脉 智能体实战操作与接力维护手册 (Agent Operational Handbook)

> **致所有接手本项目的 AI Agent 伙伴**：  
> 本手册凝聚了前序 Agent 在开发、重构、调试、测试与发布全生命周期中积累的全部实战经验与踩坑教训。  
> 请在动工前完整研读本手册；并在完成新功能、解决复杂疑难 Bug 或建立新规范后，**主动反哺更新本文档**，实现工程经验的代际传承与可持续演进。

---

## 目录
1. [项目定位与核心架构](#1-项目定位与核心架构)
2. [环境锚定与开发终端指令集](#2-环境锚定与开发终端指令集)
3. [C# 5.0 语法铁律与架构避坑宝典](#3-c-50-语法铁律与架构避坑宝典)
4. [版本发布标准作业程序 (Release SOP)](#4-版本发布标准作业程序-release-sop)
5. [杀毒软件误报与数字签名防御体系](#5-杀毒软件误报与数字签名防御体系)
6. [测试驱动与自动化回归体系](#6-测试驱动与自动化回归体系)
7. [智能体接力公约与知识飞轮机制](#7-智能体接力公约与知识飞轮机制)

---

## 1. 项目定位与核心架构

### 1.1 项目愿景
**FerrisPulse · 灵脉** 诞生于纯粹的极客初衷：**彻底干掉官方动辄 1GB、常驻 10+ 后台守护服务的臃肿驱动全家桶**（如 Razer Synapse 雷云、Logitech G HUB 等）。
提供纯原生、免驱级、常驻内存仅约 12MB 的跨品牌外设统一调度中心（原生支持雷蛇、罗技、雷柏、瓦尔基里、Apple/Beats、HyperX 等）。

### 1.2 模块分层结构
严禁单文件巨石化，所有代码严格遵守分层：
- `src/Core/`: 底层 Win32 P/Invoke (`NativeMethods.cs`)、注册表持久化 (`ConfigManager.cs`)、自启动管理 (`StartupManager.cs`)、程序入口 (`Program.cs`)。
- `src/Hardware/`: 品牌私有 HID 报文逆向解析与通信总线（Razer、Logitech、Rapoo、Valkyrie、Apple/Beats、HyperX 等）。
- `src/Models/`: 强类型数据模型与枚举 (`DeviceCategory`, `MouseBatteryInfo` 等)。
- `src/Services/`: 后台服务（全屏游戏探测 `AutoGameManager.cs`、自更新 `UpdateManager.cs`、提示音 `SoundFeedbackService.cs`）。
- `src/UI/`: 
  - `Forms/MainForm.*.cs`: 主窗体分部类体系（`MainForm.cs` 生命周期、`MainForm.UI.cs` 控件排版、`MainForm.Hardware.cs` 硬件轮询与事件响应、`MainForm.Tray.cs` 托盘渲染、`MainForm.Events.cs` 系统事件）。
  - `Forms/UpdateNoticeForm.cs`: 自更新弹窗。
  - `Forms/GameManagerForm.cs`: 游戏进程管理。
  - `Controls/`: 现代暗黑圆角发光控件体系（`SegmentedBar`, `CyberToggle`, `CyberDpiCard` 等）。

---

## 2. 环境锚定与开发终端指令集

### 2.1 工作区物理路径（唯一合法）
- **根目录**：`D:\FerrisPulse · 灵脉\`
- ⚠️ **路径陷阱注意**：
  - Windows 环境下路径含有中文字符与中点符号（`·`），在 PowerShell 中执行命令时，必须先设置控制台输出编码：
    ```powershell
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8;
    Set-Location -LiteralPath 'D:\FerrisPulse · 灵脉'
    ```
  - .NET 静态方法（如 `[System.IO.File]::ReadAllText`）默认依赖进程当前目录，在编写维护脚本时，必须使用绝对路径或 `(Resolve-Path "$PSScriptRoot\..").Path` 解析，严禁使用裸相对路径。

### 2.2 核心指令速查表

| 操作需求 | 执行命令 | 说明 |
| :--- | :--- | :--- |
| **纯净原生编译** | `cmd.exe /c "build.bat"` | 调用 C# 5.0 `csc.exe` 纯源码直编，产出 `FerrisPulse.exe` |
| **全量自动化测试** | `powershell -ExecutionPolicy Bypass -File tools/run_all_tests.ps1` | 执行 40+ 项测试用例，包含看门狗超时机制 |
| **BOM 编码强制校准** | `python tools/ensure_boms_safe.py` | 递归校准所有 `.cs` 和 `.ps1` 包含 UTF-8 BOM |
| **便携版压缩包打包** | `powershell -ExecutionPolicy Bypass -File tools/build_release_zip.ps1 -Version "2.1.1"` | 自动打包 `FerrisPulse_v2.1.1_Portable.zip` |
| **全自动双平台发布** | `powershell -ExecutionPolicy Bypass -File tools/publish_release.ps1 -Version "2.1.1"` | 读取凭据、编译、校验、打 Tag、推 GitHub & Gitee |

---

## 3. C# 5.0 语法铁律与架构避坑宝典

### 3.1 编译器与语言等级严格锁定
- **编译器**：`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`
- **语言标准**：严格 **C# 5.0**（严禁任何 C# 6.0+ 特性，否则编译立即报错）：
  - ❌ 禁止字符串插值：`$"Name: {name}"` ➡️ 必须使用 `string.Format("Name: {0}", name)` 或 `+` 拼接。
  - ❌ 禁止空条件运算符：`action?.Invoke()` ➡️ 必须使用 `if (action != null) action();`。
  - ❌ 禁止 `nameof(...)` ➡️ 必须使用硬编码字面量 `"propertyName"`。
  - ❌ 禁止表达式主体成员：`int Count => list.Count;` ➡️ 必须使用完整的 `{ get { return list.Count; } }`。
  - ❌ 禁止自动属性赋初值：`public int V { get; set; } = 1;` ➡️ 必须在构造函数中赋值。

### 3.2 文件编码安全（UTF-8 with BOM）
- 所有 `.cs` 文件**必须带有 UTF-8 BOM 签名**（`EF BB BF`），编译时 `build.bat` 严格携带 `/codepage:65001`。
- 修改代码后，如果不确定编辑器是否破坏了 BOM，运行 `python tools/ensure_boms_safe.py` 自动补全。

### 3.3 UI 状态同步与布局避坑（血泪教训）
1. **冷启动 0 尺寸防范**：
   - 动态卡片（如电竞 DPI 档位、电竞回报率按钮）在应用启动或设备切换时，必须显式调用 `RelayoutPerformanceControls()`。
   - 严禁让按钮保持在 `{Width=0, Height=0}` 状态，必须在展开或赋值后立即完成绝对坐标与尺寸计算。
2. **设备切换残留清理**：
   - 在 `UpdatePerformanceSection` 中切换设备时，必须最优先更新 `selectedDevice = info`。
   - 必须先彻底清空或隐藏非当前设备支持的控件，再重新挂载新设备的性能控件。
3. **音频播放防截断**：
   - 提示音播放不能依赖可能被垃圾回收或过早 Dispose 的短生命周期对象。
   - 多次连续播放需做好状态同步，避免高频切换时音频被强制中断。

---

## 4. 版本发布标准作业程序 (Release SOP)

发布新版本是一项严密的工程操作，任何 Agent 在执行发布时必须严格遵循以下步骤：

### 步骤 1：版本契约四要素对齐
1. **`src/Properties/AssemblyInfo.cs`**：
   ```csharp
   [assembly: AssemblyVersion("2.1.1.0")]
   [assembly: AssemblyFileVersion("2.1.1.0")]
   [assembly: AssemblyInformationalVersion("2.1.1-Release")]
   ```
2. **`version.json`**：
   - 更新 `latestVersion`（如 `"2.1.1"`）。
   - 更新 `releaseDate`（当天日期，如 `"2026-10-20"`）。
   - 更新 `downloadUrl` 对应版本号。
   - 维护 `changelog` 数组。
3. **`CHANGELOG.md`**：
   - 顶部追加 `## 🚀 [vX.Y.Z] - YYYY-MM-DD` 详细更新日志。
4. **Git Tag**：
   - 保持标签命名为 `vX.Y.Z`。

### 步骤 2：纯净编译与 Hash/大小计算
```powershell
# 杀掉残留进程并编译
Stop-Process -Name "FerrisPulse" -Force -ErrorAction SilentlyContinue
cmd.exe /c "build.bat"

# 获取新文件的真实哈希与大小并同步回 version.json
$sha256 = (Get-FileHash -Path "FerrisPulse.exe" -Algorithm SHA256).Hash.ToLower()
$fileSize = (Get-Item "FerrisPulse.exe").Length
```

### 步骤 3：全量回归测试验证（一票否决制）
必须运行 `powershell -ExecutionPolicy Bypass -File tools/run_all_tests.ps1`，确保全部测试用例 **100% PASS**（40+ 项全绿），方可进入发布。

### 步骤 4：自动化流水线发布
直接调用发布脚本：
```powershell
powershell -ExecutionPolicy Bypass -File tools/publish_release.ps1 -Version "2.1.1" -Title "FerrisPulse · 灵脉 v2.1.1 正式版"
```
脚本将全自动完成：Git 提交 ➡️ 打 Tag ➡️ 推送 GitHub & Gitee ➡️ GitHub Releases 资产上传 ➡️ Gitee Releases 资产上传。

---

## 5. 杀毒软件误报与数字签名防御体系

### 5.1 误报核心成因
- **缺少商业 EV 证书**：未签名的二进制文件从公网下载，SmartScreen 和 Defender 默认信誉为零。
- **底层硬件操作特征**：直接读写 HID、扫描游戏窗口句柄、注册表自启动、原子自更新替换。

### 5.2 软件代码防御（防红叉崩溃）
- 在 `UpdateManager.cs` 和 `UpdateNoticeForm.cs` 中，对所有下载与文件校验逻辑实施安全拦截。
- 捕获 `0x800700E1 (ERROR_VIRUS_INFECTED)` 时，严禁将异常抛给未处理的全局异常处理器（避免弹红叉堆栈），而是优雅提示：
  *“⚠️ 更新文件被系统安全软件误拦截。软件完全开源安全，请在安全中心放行，或手动下载便携版 Zip。”*

### 5.3 官方白名单与证书通道
1. **微软安全情报提交 (WDSI)**：
   每次发布重大版本，访问 [Microsoft Defender Security Intelligence](https://www.microsoft.com/en-us/wdsi/filesubmission)，以 "Software developer" 身份提交 `FerrisPulse.exe`，通常 24 小时内全网 Defender 白名单放行。
2. **SignPath.io 权威开源签名体系**：
   - 本项目已配置 GitHub Actions 自动签名流水线：`.github/workflows/build-and-sign.yml`。
   - 依赖的仓库 Secrets：`SIGNPATH_API_TOKEN` 与 `SIGNPATH_ORGANIZATION_ID`。
   - 每次打 Tag 推送，SignPath 硬件云端自动签名，彻底解决客户端信任问题。

---

## 6. 测试驱动与自动化回归体系

- **测试用例存放位置**：`tests/test_*.ps1`
- **编写原则**：
  - 任何针对 Bug 的修复，必须附带一个能精确复现并验证修复的独立 PowerShell 测试脚本。
  - 严禁依赖 GUI 人工肉眼点击；全部通过反射（Reflection）注入 Mock 数据，断言窗体内部控件状态、坐标与尺寸。
  - 所有测试脚本在 `tools/run_all_tests.ps1` 中由 8 秒看门狗守护，防止测试脚本意外死循环卡死流水线。

---

## 7. 智能体接力公约与知识飞轮机制

为了保证任何 Agent 接手项目后能无缝协同，特订立以下**四大行动公约**：

1. **上手必读，以终为始**：
   任何新 Agent 接手本对话或工作区时，**第一件事必须阅读 `AGENTS.md` 和本手册 (`docs/AGENT_HANDBOOK.md`)**，快速对齐架构认知与铁律约束。
2. **零垃圾文件残留 (Zero Scatter Policy)**：
   根目录下严禁散落任何临时测试文件（`scratch/` 脚本用完即删，或移入 `tools/` 正式归档）。任务完成前必须执行 `git status` 确认工作区纯净。
3. **零二进制提交 (Zero Binary in Git)**：
   严禁将 `FerrisPulse.exe`、`*.zip` 等编译产物使用 `git add` 提交到仓库历史中，保持 Git 仓库极致轻量。
4. **知识反哺制度 (Living Knowledge Flywheel)**：
   当你在后续开发中：
   - 发现并攻坚了一个新的 Windows 系统/驱动 Bug；
   - 接入了新的外设品牌协议（如达摩鲨、蜻蜓、魔导等）；
   - 优化了打包、签名或发布流水线；  
   **你必须主动修改本手册，将最新的经验、坑点与应对策略记录下来**，让项目的智慧代代相传，真正实现可持续演进！