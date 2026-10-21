# 电量管家 (FerrisPulse) Agent Rules & Superpowers Configuration

> 本文件为“电量管家”工作区的最高指令文件。在本项目中，Superpowers 默认开启，且必须与项目的 7 大开发铁律及智能体实战手册协同执行。

---

## 1. Superpowers 项目级默认启用规范 (Project-Level Superpowers Active)

<EXTREMELY-IMPORTANT>
在“电量管家”项目中，Superpowers 工程方法论为【默认开启 (Always On)】状态：

1. **新功能 / 需求开发**：
   - 编写任何代码之前，必须先调用 `brainstorming` 技能，通过对话明确意图、推演设计方案并获得确认。
   - 确认设计后，使用 `writing-plans` 制定分步实现计划，严格遵循决策记录与测试断言规范。
   - 执行阶段遵循 `test-driven-development` 与 `executing-plans`。

2. **缺陷排查 / Bug 修复**：
   - 遇到任何异常、逻辑缺陷或报错，必须先调用 `systematic-debugging` 技能，严格执行四步法（复现 -> 追踪根因 -> 根除修复 -> 回归验证），严禁盲目打补丁或掩盖症状。

3. **任务跟踪与验证**：
   - 多步计划使用 Task Artifacts (`write_to_file` 配合 `ArtifactType: "task"`) 维护并用 `replace_file_content` 打勾。
   - 宣布完成前，必须执行 `verification-before-completion` 验证实际编译与运行输出。
</EXTREMELY-IMPORTANT>

---

## 2. FerrisPulse 维护规范与工程准则（11 大铁律）

本项目开发同时必须严格遵守 [AGENT_RULES.md](file:///D:/FerrisPulse%20%C2%B7%20%E7%81%B5%E8%84%89/AGENT_RULES.md) 中的底层铁律：

1. **语言标准与编译器基准**: 严格 C# 5.0 / .NET Framework 4.0，使用 Windows 原生自带 `csc.exe` 编译。严禁使用 C# 6.0+ 语法（禁止 `$"..."` 插值、禁止 `?.` 空条件运算符、禁止 `nameof` 等）。
2. **零外部依赖铁律**: 仅允许引用 .NET 4.0 核心程序集。系统交互严格采用 Win32 P/Invoke，严禁引入 NuGet 包或第三方 DLL。
3. **文件编码安全**: 所有 `.cs`, `.bat`, `.md`, `.ps1` 源码文件必须以 **UTF-8 带签名 (BOM)** 保存，编译始终加 `/codepage:65001`。
4. **模块化工程架构**: 禁止单文件巨石化，严格分层存放于 `src/Core/`, `src/Hardware/`, `src/Models/`, `src/Services/`, `src/UI/`。
5. **任务栏自愈与自启动守护**: 必须维护注册表自启动与 `WM_TASKBARCREATED` 托盘重建自愈逻辑；桌面图标绝不静默自建，严格由用户托盘手动触发。
6. **维护准则注释保留**: 每个代码文件头部必须永久保留 `// ⚠️ AI 维护准则 (AI MAINTENANCE DIRECTIVE - DO NOT REMOVE) ⚠️`。
7. **工作区锁定与文件卫生规范**: 唯一合法工作区为 `D:\FerrisPulse · 灵脉\`；根目录严禁倾倒临时文件；严禁向 Git 仓库提交二进制（`*.exe`, `*.zip` 等）。
8. **DWM 原生弹窗动效与抗白框**: 严禁 `AnimateWindow` 软件模拟；呼出采用 `this.RecreateHandle()` 重置呈现状态机，重现原生平滑展开微光，拦截 `WM_ERASEBKGND` 彻底消除浅色底色闪烁。
9. **键盘 HID 0 权限握手与物理隔离**: 键盘 HID 句柄必须传权限 `0`（`FILE_READ_ATTRIBUTES`）避开 Windows 内核防监听独占锁，恢复 `HidD_GetFeature` 电量读取；键鼠多模外设必须在 `DeviceManager` 实行双通道物理隔离。
10. **自动化测试防锁死铁律**: 测试脚本加载二进制必须采用 `[System.IO.File]::ReadAllBytes` 全内存反射装配，严禁 `Add-Type -Path` 产生强互斥文件句柄锁死导致 `CS0016` 编译报错。
11. **平台路径注入避坑铁律**: Windows 下工作区路径遇平台会话压缩注入异常时，严禁盲目派生后台死循环重试，及时引导用户通过原生终端或双击 `build.bat` 极速编译。

---

## 3. 智能体操作宝典与发布全流程索引 (Operational Handbook & Release SOP)

任何接手本项目的 Agent，在处理版本发布、杀软误报、UI 状态机或复杂硬件 Bug 时，必须参阅深度手册：  
👉 **[docs/AGENT_HANDBOOK.md](file:///D:/FerrisPulse%20%C2%B7%20%E7%81%B5%E8%84%89/docs/AGENT_HANDBOOK.md)**

### 3.1 极速发布新版本 SOP 摘要 (Quick Release Flow)
1. **对齐版本号**：
   - `src/Properties/AssemblyInfo.cs` ➡️ `AssemblyVersion("X.Y.Z.0")` 等
   - `version.json` ➡️ `latestVersion`, `downloadUrl`, `changelog`
   - `CHANGELOG.md` ➡️ 顶部追加 `## 🚀 [vX.Y.Z] - YYYY-MM-DD`
2. **构建与计算 Hash**：
   - `Stop-Process -Name "FerrisPulse" -Force -ErrorAction SilentlyContinue; cmd.exe /c "build.bat"`
   - 计算 `FerrisPulse.exe` 的 SHA256 与 FileSize，写回 `version.json`。
3. **回归验证**：
   - 运行全量测试：`powershell -ExecutionPolicy Bypass -File tools/run_all_tests.ps1`，确保全部 PASS。
4. **一键双平台发布**：
   - `powershell -ExecutionPolicy Bypass -File tools/publish_release.ps1 -Version "X.Y.Z"`（自动打 Tag、推 GitHub/Gitee 并上传 Release 附件）。

### 3.2 发布后本地“留旧测新”验证铁律 (Local Test vs Remote Release SOP)
- **核心原则**：云端已发布最新版本后，**本地 `AssemblyInfo.cs` 必须立即回滚为上一版本（如 2.0.4.0）并重新执行 `build.bat`**。
- **目的**：保证本地 `FerrisPulse.exe` 处于旧版本，以供用户或测试者在本地运行并亲自触发自更新弹窗、下载校验、平滑替换与重启的完整闭环实测。
- **未验证前禁止提交**：本地处于旧版本的 `AssemblyInfo.cs` 保留在 Git 工作区未提交状态，直至用户确认更新完全成功。

### 3.3 核心技术避坑精要 (Critical Technical Traps)
1. **原生 DWM 弹窗动效（抗白框闪烁）**：
   - 严禁使用 `AnimateWindow`（会产生深色模式下刺眼的白框闪烁并破坏合成）。
   - 呼出时使用 `this.RecreateHandle()` 重置 DWM 呈现状态机，完美重现与冷启动一致的原生平滑展开动效，并由 `WM_ERASEBKGND` 拦截彻底消除白底。
2. **键盘 HID 0 权限握手**：
   - Windows 内核对键盘设备有独占防监听保护，传 `GENERIC_READ` 必报 Access Denied (5)。打开键盘句柄必须传 `0` 权限（`FILE_READ_ATTRIBUTES`），方可成功执行 `HidD_GetFeature` 读取物理电量。
3. **Apple/Beats 蓝牙生态防路人误扫**：
   - 强制比对 Windows 经典蓝牙配对白名单，未配对的 BLE 广播一律过滤；严格剔除 `Wireless iAP` 等驱动层虚拟端点伪名称。
4. **测试防锁死（全内存反射）**：
   - PowerShell 测试脚本必须使用 `[System.IO.File]::ReadAllBytes` 载入内存装配，严禁 `Add-Type -Path` 锁死 `FerrisPulse.exe` 导致后续编译 `CS0016` 报错。
5. **换行符腐败防范**：
   - 防范 Windows 下文本追加产生的 `\r\r\n` Double-CR 陷阱，常备 `python tools/ensure_boms_safe.py` 自动化核验与修复。

---

## 4. 智能体接力公约与知识持续反哺机制 (Living Knowledge Flywheel)

<IMPORTANT>
**可持续化知识公约 (Mandatory Relay Protocol)**：
1. **上手第一步**：任何新 Agent 介入本项目时，**必须首先通读本文件 (`AGENTS.md`) 与 `docs/AGENT_HANDBOOK.md`**。
2. **完工反哺义务**：后续任何 Agent 在解决复杂疑难 Bug、接入新品牌设备、优化发布流程或发现新安全陷阱后，**必须主动编辑并更新 `docs/AGENT_HANDBOOK.md`**，将新经验与避坑方案固化沉淀，禁止让后续 Agent 踩重复的坑！
</IMPORTANT>