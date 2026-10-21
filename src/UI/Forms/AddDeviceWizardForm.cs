﻿// ============================================================================
// 模块名称: AddDeviceWizardForm.cs
// 所属区域: UI/Forms (业务对话框层)
// 核心职责:
//   新外设即插即用添加向导窗口，包含全系统 HID 原始设备嗅探探测、实时读写报文连通性校验、自定义设备别名与品类归类（DPI 自适应）。
// 依赖关系: Controls.*, Hardware.DeviceManager, Core.ConfigManager, Models.CustomDeviceConfig
//
// ⚠️ AI 维护准则 (AI MAINTENANCE DIRECTIVE - DO NOT REMOVE) ⚠️:
// 1. [契约同步更新]: 任何 AI Agent 在修改本文件逻辑、属性或绘图逻辑时，【必须】同步更新上方说明。
// 2. [C# 5 兼容铁律]: 严禁使用 C# 6+ 语法（❌ 严禁 $"..." 插值，必须使用 string.Format 或 + 拼接）。
// 3. [编码格式锁定]: 本文件必须严格保存为【UTF-8 with BOM】编码。
// ============================================================================

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Threading;
using System.Windows.Forms;

namespace RazerBatteryTray
{
    public class AddDeviceWizardForm : DpiAwareForm
    {
        public string AddedDeviceId { get; private set; }

        private ListBox lstDevices;
        private ModernInputBox txtCustomName;
        private ModernDarkDropdown cmbCategory;
        private Label lblTestStatus;
        private ModernButton btnScan;
        private ModernButton btnSave;
        private ModernButton btnCancel;
        private ModernButton btnCopyPrompt;
        private ModernButton btnAiTools;
        private WizardRadarBadge radarBadge;
        private ScanningBeamControl beamControl;
        private System.Windows.Forms.Timer autoScanDebounceTimer;
        private System.Windows.Forms.Timer copyFeedbackTimer;
        private bool isScanning = false;
        private const int WM_DEVICECHANGE = 0x0219;
        private List<CustomDeviceConfig> scannedList = new List<CustomDeviceConfig>();
        private HashSet<string> existingIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        protected override void WndProc(ref Message m)
        {
            base.WndProc(ref m);
            if (m.Msg == WM_DEVICECHANGE)
            {
                if (autoScanDebounceTimer == null)
                {
                    autoScanDebounceTimer = new System.Windows.Forms.Timer();
                    autoScanDebounceTimer.Interval = 600;
                    autoScanDebounceTimer.Tick += (s, ev) => {
                        autoScanDebounceTimer.Stop();
                        PerformScanAsync();
                    };
                }
                autoScanDebounceTimer.Stop();
                autoScanDebounceTimer.Start();
            }
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            base.OnFormClosed(e);
            if (autoScanDebounceTimer != null)
            {
                autoScanDebounceTimer.Stop();
                autoScanDebounceTimer.Dispose();
                autoScanDebounceTimer = null;
            }
            if (copyFeedbackTimer != null)
            {
                copyFeedbackTimer.Stop();
                copyFeedbackTimer.Dispose();
                copyFeedbackTimer = null;
            }
        }

        public AddDeviceWizardForm() : this(null, 1.0f) { }

        public AddDeviceWizardForm(List<MouseBatteryInfo> existing) : this(existing, 1.0f) { }

        public AddDeviceWizardForm(float scale) : this(null, scale) { }

        public AddDeviceWizardForm(List<MouseBatteryInfo> existing, float scale) : base(scale)
        {
            if (existing != null)
            {
                foreach (var d in existing)
                {
                    if (DeviceManager.IsDeviceHidden(d.DeviceId)) continue;
                    if (!string.IsNullOrEmpty(d.HardwareFingerprint) && DeviceManager.IsDeviceHidden(d.HardwareFingerprint)) continue;

                    existingIds.Add(d.DeviceId);
                    var v1 = DeviceManager.GetDeviceIdVariants(d.DeviceId);
                    for (int i = 0; i < v1.Count; i++) existingIds.Add(v1[i]);

                    if (!string.IsNullOrEmpty(d.HardwareFingerprint))
                    {
                        existingIds.Add(d.HardwareFingerprint);
                        var v2 = DeviceManager.GetDeviceIdVariants(d.HardwareFingerprint);
                        for (int i = 0; i < v2.Count; i++) existingIds.Add(v2[i]);
                    }
                }
            }

            this.Text = "添加与配置外设向导";
            this.ClientSize = new Size((int)(430 * dpiScale), (int)(576 * dpiScale));
            this.BackColor = Color.FromArgb(18, 19, 23);
            this.ForeColor = Color.White;
            this.StartPosition = FormStartPosition.CenterParent;
            this.FormBorderStyle = FormBorderStyle.FixedDialog;
            this.MaximizeBox = false;
            this.MinimizeBox = false;

            int pad = (int)(16 * dpiScale);

            // Header Radar Badge
            radarBadge = new WizardRadarBadge();
            radarBadge.DpiScale = dpiScale;
            radarBadge.Size = new Size((int)(24 * dpiScale), (int)(24 * dpiScale));
            radarBadge.Location = new Point(pad, (int)(13 * dpiScale));
            this.Controls.Add(radarBadge);

            // Row 1: Title on left, Scan button on right
            var lblTitle = new Label();
            lblTitle.Text = "添加与配置外设向导";
            lblTitle.Font = new Font("Microsoft YaHei UI", 11F, FontStyle.Bold);
            lblTitle.ForeColor = Color.FromArgb(240, 245, 255);
            lblTitle.Location = new Point(pad + (int)(28 * dpiScale), (int)(15 * dpiScale));
            lblTitle.AutoSize = true;
            this.Controls.Add(lblTitle);

            btnScan = new ModernButton();
            btnScan.Text = "🔄 重新扫描";
            btnScan.Font = new Font("Microsoft YaHei UI", 8.8F, FontStyle.Bold);
            btnScan.NormalColor = Color.FromArgb(32, 36, 48);
            btnScan.HoverColor = Color.FromArgb(46, 52, 68);
            btnScan.PressedColor = Color.FromArgb(24, 28, 38);
            btnScan.BorderColor = Color.FromArgb(60, 68, 88);
            btnScan.TextColor = Color.FromArgb(220, 230, 250);
            int scanW = (int)(100 * dpiScale);
            btnScan.Location = new Point(this.ClientSize.Width - pad - scanW, (int)(12 * dpiScale));
            btnScan.Size = new Size(scanW, (int)(28 * dpiScale));
            btnScan.Click += (s, e) => PerformScanAsync();
            this.Controls.Add(btnScan);

            // Row 2: Subtitle
            var lblSub = new Label();
            lblSub.Text = "自动扫描当前在线外设，支持修改昵称与设备分类：";
            lblSub.Font = new Font("Microsoft YaHei UI", 8.5F);
            lblSub.ForeColor = Color.FromArgb(145, 155, 175);
            lblSub.Location = new Point(pad, (int)(46 * dpiScale));
            lblSub.Size = new Size(this.ClientSize.Width - (pad * 2), (int)(20 * dpiScale));
            this.Controls.Add(lblSub);

            // Scanning Laser Beam Animation Bar
            beamControl = new ScanningBeamControl();
            beamControl.Location = new Point(pad, (int)(68 * dpiScale));
            beamControl.Size = new Size(this.ClientSize.Width - (pad * 2), (int)(3 * dpiScale));
            beamControl.Visible = false;
            this.Controls.Add(beamControl);

            // Row 3: Scanned Devices List (Owner Drawn Dark Cards)
            lstDevices = new ListBox();
            lstDevices.BackColor = Color.FromArgb(18, 19, 23);
            lstDevices.ForeColor = Color.FromArgb(235, 240, 250);
            lstDevices.BorderStyle = BorderStyle.None;
            lstDevices.Font = new Font("Microsoft YaHei UI", 9.2F);
            lstDevices.DrawMode = DrawMode.OwnerDrawFixed;
            lstDevices.ItemHeight = (int)(52 * dpiScale);
            lstDevices.Location = new Point(pad, (int)(72 * dpiScale));
            lstDevices.Size = new Size(this.ClientSize.Width - (pad * 2), (int)(150 * dpiScale));
            lstDevices.DrawItem += LstDevices_DrawItem;
            lstDevices.SelectedIndexChanged += (s, e) => OnDeviceSelected();
            lstDevices.HandleCreated += (s, e) => {
                try { ModernThemeHelper.SetWindowTheme(lstDevices.Handle, "DarkMode_Explorer", null); } catch { }
            };
            this.Controls.Add(lstDevices);

            // Row 4: Custom Nickname
            int formY = (int)(230 * dpiScale);
            var lblName = new Label();
            lblName.Text = "自定义昵称:";
            lblName.Font = new Font("Microsoft YaHei UI", 8.8F);
            lblName.ForeColor = Color.FromArgb(170, 180, 200);
            lblName.Location = new Point(pad, formY + 5);
            lblName.AutoSize = true;
            this.Controls.Add(lblName);

            txtCustomName = new ModernInputBox();
            txtCustomName.DpiScale = dpiScale;
            txtCustomName.Location = new Point(pad + (int)(95 * dpiScale), formY);
            txtCustomName.Size = new Size(this.ClientSize.Width - pad * 2 - (int)(95 * dpiScale), (int)(30 * dpiScale));
            this.Controls.Add(txtCustomName);

            // Row 5: Category Dropdown (ModernDarkDropdown)
            formY += (int)(36 * dpiScale);
            var lblCat = new Label();
            lblCat.Text = "外设类别:";
            lblCat.Font = new Font("Microsoft YaHei UI", 8.8F);
            lblCat.ForeColor = Color.FromArgb(170, 180, 200);
            lblCat.Location = new Point(pad, formY + 5);
            lblCat.AutoSize = true;
            this.Controls.Add(lblCat);

            cmbCategory = new ModernDarkDropdown();
            cmbCategory.DpiScale = dpiScale;
            cmbCategory.Items.Add("🖱️ 鼠标 (Mouse)");
            cmbCategory.Items.Add("⌨️ 键盘 (Keyboard)");
            cmbCategory.Items.Add("🎧 头戴式耳机 (Headset)");
            cmbCategory.Items.Add("🦻 入耳式耳机 (Earbuds)");
            cmbCategory.Items.Add("🎮 游戏手柄 (Gamepad)");
            cmbCategory.Items.Add("📡 接收器 / 拓展坞 (Dongle)");
            cmbCategory.Items.Add("🔌 通用外设 (Generic)");
            cmbCategory.SelectedIndex = 0;
            cmbCategory.Location = new Point(pad + (int)(95 * dpiScale), formY);
            cmbCategory.Size = new Size(this.ClientSize.Width - pad * 2 - (int)(95 * dpiScale), (int)(30 * dpiScale));
            this.Controls.Add(cmbCategory);

            // Row 6: Live Status Box
            formY += (int)(38 * dpiScale);
            lblTestStatus = new Label();
            lblTestStatus.Text = "请从上方列表选择一个设备";
            lblTestStatus.Font = new Font("Microsoft YaHei UI", 8.8F, FontStyle.Bold);
            lblTestStatus.ForeColor = Color.FromArgb(0, 230, 118);
            lblTestStatus.Location = new Point(pad, formY);
            lblTestStatus.Size = new Size(this.ClientSize.Width - (pad * 2), (int)(38 * dpiScale));
            this.Controls.Add(lblTestStatus);

            // Row 7: AI Dedicated Card (Self Developer Hub)
            int cardW = this.ClientSize.Width - (pad * 2);
            int cardH = (int)(110 * dpiScale);
            Panel pnlAiAdapter = new Panel();
            pnlAiAdapter.Location = new Point(pad, (int)(350 * dpiScale));
            pnlAiAdapter.Size = new Size(cardW, cardH);
            pnlAiAdapter.BackColor = Color.FromArgb(22, 25, 34);
            pnlAiAdapter.Paint += (s, e) =>
            {
                Graphics g = e.Graphics;
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
                Rectangle rect = new Rectangle(0, 0, pnlAiAdapter.Width - 1, pnlAiAdapter.Height - 1);
                using (GraphicsPath path = RoundedCard.GetRoundedRectangle(rect, (int)(7 * dpiScale)))
                {
                    using (SolidBrush bg = new SolidBrush(Color.FromArgb(22, 25, 34)))
                    {
                        g.FillPath(bg, path);
                    }
                    using (Pen borderPen = new Pen(Color.FromArgb(46, 54, 72), 1f))
                    {
                        g.DrawPath(borderPen, path);
                    }
                }
            };
            this.Controls.Add(pnlAiAdapter);

            int cPad = (int)(12 * dpiScale);

            Label lblAiTitle = new Label();
            lblAiTitle.Text = "💡 找不到你的设备？试试自己做自己的开发者！";
            lblAiTitle.Font = new Font("Microsoft YaHei UI", 9F, FontStyle.Bold);
            lblAiTitle.ForeColor = Color.FromArgb(240, 245, 255);
            lblAiTitle.Location = new Point(cPad, (int)(10 * dpiScale));
            lblAiTitle.AutoSize = true;
            pnlAiAdapter.Controls.Add(lblAiTitle);

            Label lblAiSub = new Label();
            lblAiSub.Text = "借助本地 AI Agent 工具自动探测外设通信与电量指令。";
            lblAiSub.Font = new Font("Microsoft YaHei UI", 8.2F);
            lblAiSub.ForeColor = Color.FromArgb(145, 155, 175);
            lblAiSub.Location = new Point(cPad, (int)(32 * dpiScale));
            lblAiSub.Size = new Size(cardW - cPad * 2, (int)(18 * dpiScale));
            pnlAiAdapter.Controls.Add(lblAiSub);

            int btnCopyW = (int)(205 * dpiScale);
            int btnAiH = (int)(32 * dpiScale);
            int btnAiY = (int)(58 * dpiScale);

            btnCopyPrompt = new ModernButton();
            btnCopyPrompt.Text = "📋 复制 AI 适配提示词";
            btnCopyPrompt.Font = new Font("Microsoft YaHei UI", 8.5F, FontStyle.Bold);
            btnCopyPrompt.NormalColor = Color.FromArgb(32, 42, 60);
            btnCopyPrompt.HoverColor = Color.FromArgb(46, 60, 86);
            btnCopyPrompt.PressedColor = Color.FromArgb(22, 30, 44);
            btnCopyPrompt.BorderColor = Color.FromArgb(64, 82, 116);
            btnCopyPrompt.TextColor = Color.FromArgb(220, 235, 255);
            btnCopyPrompt.Location = new Point(cPad, btnAiY);
            btnCopyPrompt.Size = new Size(btnCopyW, btnAiH);
            btnCopyPrompt.Click += (s, e) =>
            {
                try
                {
                    Clipboard.SetText(GetAiAdaptationPrompt());
                    btnCopyPrompt.Text = "✓ 提示词已复制！";
                    btnCopyPrompt.NormalColor = Color.FromArgb(0, 160, 80);
                    btnCopyPrompt.HoverColor = Color.FromArgb(0, 180, 90);
                    btnCopyPrompt.BorderColor = Color.FromArgb(0, 200, 100);
                    if (copyFeedbackTimer == null)
                    {
                        copyFeedbackTimer = new System.Windows.Forms.Timer();
                        copyFeedbackTimer.Interval = 2500;
                        copyFeedbackTimer.Tick += (s2, e2) =>
                        {
                            copyFeedbackTimer.Stop();
                            btnCopyPrompt.Text = "📋 复制 AI 适配提示词";
                            btnCopyPrompt.NormalColor = Color.FromArgb(32, 42, 60);
                            btnCopyPrompt.HoverColor = Color.FromArgb(46, 60, 86);
                            btnCopyPrompt.BorderColor = Color.FromArgb(64, 82, 116);
                        };
                    }
                    copyFeedbackTimer.Stop();
                    copyFeedbackTimer.Start();
                }
                catch { }
            };
            pnlAiAdapter.Controls.Add(btnCopyPrompt);

            int btnToolsW = cardW - cPad * 2 - btnCopyW - (int)(10 * dpiScale);
            btnAiTools = new ModernButton();
            btnAiTools.Text = "🚀 获取推荐 AI 工具 ↗";
            btnAiTools.Font = new Font("Microsoft YaHei UI", 8.5F, FontStyle.Bold);
            btnAiTools.NormalColor = Color.FromArgb(28, 34, 48);
            btnAiTools.HoverColor = Color.FromArgb(40, 50, 70);
            btnAiTools.PressedColor = Color.FromArgb(20, 24, 34);
            btnAiTools.BorderColor = Color.FromArgb(56, 70, 98);
            btnAiTools.TextColor = Color.FromArgb(0, 210, 255);
            btnAiTools.Location = new Point(cPad + btnCopyW + (int)(10 * dpiScale), btnAiY);
            btnAiTools.Size = new Size(btnToolsW, btnAiH);
            btnAiTools.Click += (s, e) =>
            {
                using (AiToolsDialog dlg = new AiToolsDialog(dpiScale))
                {
                    dlg.ShowDialog(this);
                }
            };
            pnlAiAdapter.Controls.Add(btnAiTools);

            // Row 8: Buttons
            int btnH = (int)(36 * dpiScale);
            int btnY = (int)(524 * dpiScale);
            int cancelW = (int)(110 * dpiScale);
            int saveW = (int)(150 * dpiScale);

            btnCancel = new ModernButton();
            btnCancel.Text = "取消";
            btnCancel.Font = new Font("Microsoft YaHei UI", 9F);
            btnCancel.NormalColor = Color.FromArgb(32, 36, 48);
            btnCancel.HoverColor = Color.FromArgb(46, 52, 68);
            btnCancel.PressedColor = Color.FromArgb(24, 28, 38);
            btnCancel.BorderColor = Color.FromArgb(60, 68, 88);
            btnCancel.TextColor = Color.FromArgb(220, 230, 250);
            btnCancel.Location = new Point(this.ClientSize.Width - pad - cancelW - saveW - (int)(10 * dpiScale), btnY);
            btnCancel.Size = new Size(cancelW, btnH);
            btnCancel.Click += (s, e) => { this.DialogResult = DialogResult.Cancel; this.Close(); };
            this.Controls.Add(btnCancel);

            btnSave = new ModernButton();
            btnSave.Text = "➕ 加入监控";
            btnSave.Font = new Font("Microsoft YaHei UI", 9F, FontStyle.Bold);
            btnSave.NormalColor = Color.FromArgb(0, 200, 83);
            btnSave.HoverColor = Color.FromArgb(0, 230, 118);
            btnSave.PressedColor = Color.FromArgb(0, 170, 70);
            btnSave.BorderColor = Color.FromArgb(0, 230, 118);
            btnSave.TextColor = Color.Black;
            btnSave.Location = new Point(this.ClientSize.Width - pad - saveW, btnY);
            btnSave.Size = new Size(saveW, btnH);
            btnSave.Enabled = false;
            btnSave.Click += (s, e) => SaveSelectedDevice();
            this.Controls.Add(btnSave);

            PerformScanAsync();
        }

        private void LstDevices_DrawItem(object sender, DrawItemEventArgs e)
        {
            if (e.Index < 0 || e.Index >= scannedList.Count) return;
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;

            var item = scannedList[e.Index];
            bool isSel = (e.State & DrawItemState.Selected) == DrawItemState.Selected;
            bool isHidden = DeviceManager.IsDeviceHidden(item.DeviceId) || 
                            (!string.IsNullOrEmpty(item.HardwareFingerprint) && DeviceManager.IsDeviceHidden(item.HardwareFingerprint));
            bool already = false;
            if (!isHidden)
            {
                var vList = DeviceManager.GetDeviceIdVariants(item.DeviceId);
                if (!string.IsNullOrEmpty(item.HardwareFingerprint))
                {
                    vList.AddRange(DeviceManager.GetDeviceIdVariants(item.HardwareFingerprint));
                }
                for (int vi = 0; vi < vList.Count; vi++)
                {
                    if (existingIds.Contains(vList[vi]))
                    {
                        already = true;
                        break;
                    }
                }
            }

            // Background fill
            using (var bgBrush = new SolidBrush(Color.FromArgb(18, 19, 23)))
            {
                g.FillRectangle(bgBrush, e.Bounds);
            }

            // Card rectangle
            Rectangle cardRect = new Rectangle(e.Bounds.X + 2, e.Bounds.Y + 2, e.Bounds.Width - 4, e.Bounds.Height - 4);
            Color cardBg = isSel ? Color.FromArgb(32, 42, 58) : Color.FromArgb(25, 29, 40);
            Color cardBorder = isSel ? Color.FromArgb(0, 230, 118) : Color.FromArgb(42, 48, 65);

            using (var path = RoundedCard.GetRoundedRectangle(cardRect, (int)(7 * dpiScale)))
            {
                using (var cb = new SolidBrush(cardBg)) g.FillPath(cb, path);
                using (var cp = new Pen(cardBorder, isSel ? 1.6f : 1.0f)) g.DrawPath(cp, path);
            }

            // Left circle badge for icon
            int iconBoxSize = (int)(32 * dpiScale);
            int iconX = cardRect.X + (int)(10 * dpiScale);
            int iconY = cardRect.Y + (cardRect.Height - iconBoxSize) / 2;
            Rectangle iconRect = new Rectangle(iconX, iconY, iconBoxSize, iconBoxSize);

            Color brandCol = item.Category == DeviceCategory.Headset || item.Category == DeviceCategory.Earbuds ? Color.FromArgb(90, 160, 255) :
                             (item.Category == DeviceCategory.Keyboard ? Color.FromArgb(255, 170, 0) :
                             (item.Category == DeviceCategory.Gamepad ? Color.FromArgb(180, 100, 255) : Color.FromArgb(0, 230, 118)));

            using (var iconCircle = RoundedCard.GetRoundedRectangle(iconRect, iconBoxSize / 2))
            {
                using (var ib = new SolidBrush(Color.FromArgb(35, brandCol.R, brandCol.G, brandCol.B))) g.FillPath(ib, iconCircle);
                using (var ip = new Pen(Color.FromArgb(90, brandCol.R, brandCol.G, brandCol.B), 1f)) g.DrawPath(ip, iconCircle);
            }

            ModernThemeHelper.DrawModernDeviceIcon(g, iconRect, item.Category, brandCol);

            // Text info
            int textX = iconX + iconBoxSize + (int)(10 * dpiScale);
            string dispName = !string.IsNullOrEmpty(item.CustomName) ? item.CustomName : item.OriginalName;
            using (var nameFont = new Font("Microsoft YaHei UI", 9.2F, FontStyle.Bold))
            using (var nameBrush = new SolidBrush(Color.FromArgb(242, 246, 255)))
            {
                g.DrawString(dispName, nameFont, nameBrush, textX, cardRect.Y + (int)(7 * dpiScale));
            }

            string sub = item.Transport ?? "2.4G/USB";
            using (var subFont = new Font("Microsoft YaHei UI", 8F))
            using (var subBrush = new SolidBrush(Color.FromArgb(135, 145, 165)))
            {
                g.DrawString(sub, subFont, subBrush, textX, cardRect.Y + (int)(27 * dpiScale));
            }

            // Right tags: [已在设备库中] or [电量: X%]
            int rightX = cardRect.Right - (int)(10 * dpiScale);
            if (already)
            {
                string tag = "已在设备库中";
                using (var tagFont = new Font("Microsoft YaHei UI", 8F, FontStyle.Bold))
                {
                    var tSz = TextRenderer.MeasureText(tag, tagFont);
                    int tW = tSz.Width + (int)(10 * dpiScale);
                    int tH = (int)(20 * dpiScale);
                    int tX = rightX - tW;
                    int tY = cardRect.Y + (cardRect.Height - tH) / 2;
                    Rectangle tagRect = new Rectangle(tX, tY, tW, tH);

                    using (var tp = RoundedCard.GetRoundedRectangle(tagRect, (int)(4 * dpiScale)))
                    {
                        using (var tb = new SolidBrush(Color.FromArgb(40, 255, 183, 77))) g.FillPath(tb, tp);
                        using (var tpen = new Pen(Color.FromArgb(180, 255, 183, 77), 1f)) g.DrawPath(tpen, tp);
                    }
                    using (var tfb = new SolidBrush(Color.FromArgb(255, 195, 100)))
                    {
                        g.DrawString(tag, tagFont, tfb, tX + (int)(5 * dpiScale), tY + (int)(2 * dpiScale));
                    }
                    rightX = tX - (int)(8 * dpiScale);
                }
            }

            if (item.CachedBattery > 0)
            {
                string bStr = item.CachedBattery + "%";
                using (var bFont = new Font("Microsoft YaHei UI", 8.5F, FontStyle.Bold))
                {
                    var bSz = TextRenderer.MeasureText(bStr, bFont);
                    int bW = bSz.Width + (int)(10 * dpiScale);
                    int bH = (int)(20 * dpiScale);
                    int bX = rightX - bW;
                    int bY = cardRect.Y + (cardRect.Height - bH) / 2;
                    Rectangle bRect = new Rectangle(bX, bY, bW, bH);

                    using (var bp = RoundedCard.GetRoundedRectangle(bRect, (int)(4 * dpiScale)))
                    {
                        using (var bb = new SolidBrush(Color.FromArgb(30, 0, 230, 118))) g.FillPath(bb, bp);
                        using (var bpen = new Pen(Color.FromArgb(80, 0, 230, 118), 1f)) g.DrawPath(bpen, bp);
                    }
                    using (var bfb = new SolidBrush(Color.FromArgb(0, 230, 118)))
                    {
                        g.DrawString(bStr, bFont, bfb, bX + (int)(5 * dpiScale), bY + (int)(2 * dpiScale));
                    }
                }
            }
        }

        private void PerformScanAsync()
        {
            if (isScanning) return;
            isScanning = true;

            btnScan.Enabled = false;
            btnScan.Text = "⏳ 扫描中...";
            beamControl.Start();
            lblTestStatus.ForeColor = Color.FromArgb(0, 230, 118);
            lblTestStatus.Text = "正在检索在线 2.4G 接收器、HID 外设与蓝牙设备...";

            ThreadPool.QueueUserWorkItem((state) => {
                var tempConfigs = new List<CustomDeviceConfig>();
                var existingConfigs = DeviceManager.LoadCustomDevices();

                Func<string, string, string, string> resolveCustomName = delegate(string devId, string fallbackDisp, string origName) {
                    if (existingConfigs != null)
                    {
                        var match = existingConfigs.Find(c => c.DeviceId == devId || (!string.IsNullOrEmpty(c.HardwareFingerprint) && c.HardwareFingerprint == devId));
                        if (match != null && !string.IsNullOrEmpty(match.CustomName))
                            return match.CustomName;
                    }
                    return !string.IsNullOrEmpty(fallbackDisp) ? fallbackDisp : origName;
                };

                Func<string, DeviceCategory, DeviceCategory> resolveCategory = delegate(string devId, DeviceCategory defCat) {
                    if (existingConfigs != null)
                    {
                        var match = existingConfigs.Find(c => c.DeviceId == devId || (!string.IsNullOrEmpty(c.HardwareFingerprint) && c.HardwareFingerprint == devId));
                        if (match != null)
                            return match.Category;
                    }
                    return defCat;
                };

                // 1. Scan Razer Devices (2.4G Hyperspeed / USB)
                try
                {
                    var rzList = RazerDeviceHelper.QueryAllRazerDevices();
                    if (rzList != null)
                    {
                        foreach (var rz in rzList)
                        {
                            if (rz != null && (rz.IsConnected || rz.IsDonglePresent))
                            {
                                string normId = RazerDeviceHelper.NormalizeRazerDeviceId(rz.DeviceId);
                                if (!tempConfigs.Exists(c => c.DeviceId == normId))
                                {
                                    var cfg = new CustomDeviceConfig
                                    {
                                        DeviceId = normId,
                                        OriginalName = rz.DeviceName,
                                        CustomName = resolveCustomName(normId, rz.DisplayName, rz.DeviceName),
                                        Category = resolveCategory(normId, rz.Category),
                                        Transport = "2.4G 无线",
                                        CachedBattery = rz.BatteryPercent,
                                        HardwareFingerprint = rz.DeviceId
                                    };
                                    tempConfigs.Add(cfg);
                                }
                            }
                        }
                    }
                }
                catch { }

                // 2. Scan Rapoo Devices (2.4G / USB)
                try
                {
                    var rp = RapooDeviceHelper.QueryRapooDeviceInfo();
                    if (rp != null && (rp.IsConnected || rp.IsDonglePresent))
                    {
                        var cfg = new CustomDeviceConfig
                        {
                            DeviceId = rp.DeviceId,
                            OriginalName = rp.DeviceName,
                            CustomName = resolveCustomName(rp.DeviceId, rp.DisplayName, rp.DeviceName),
                            Category = resolveCategory(rp.DeviceId, DeviceCategory.Mouse),
                            Transport = "2.4G 无线",
                            CachedBattery = rp.BatteryPercent,
                            HardwareFingerprint = rp.DeviceId
                        };
                        tempConfigs.Add(cfg);
                    }
                }
                catch { }

                // 2.5 Scan VGN Devices (2.4G / USB)
                try
                {
                    var vgn = VgnDeviceHelper.QueryVgnDeviceInfo();
                    if (vgn != null && (vgn.IsConnected || vgn.IsDonglePresent))
                    {
                        var cfg = new CustomDeviceConfig
                        {
                            DeviceId = vgn.DeviceId,
                            OriginalName = vgn.DeviceName,
                            CustomName = resolveCustomName(vgn.DeviceId, vgn.DisplayName, vgn.DeviceName),
                            Category = resolveCategory(vgn.DeviceId, DeviceCategory.Mouse),
                            Transport = "2.4G 无线",
                            CachedBattery = vgn.BatteryPercent,
                            HardwareFingerprint = vgn.DeviceId
                        };
                        tempConfigs.Add(cfg);
                    }
                }
                catch { }

                // 2.55 Scan Logitech Devices (Lightspeed / Unifying / Nano / Wired)
                try
                {
                    var logiList = LogitechDeviceHelper.QueryAllLogitechDevices();
                    if (logiList != null)
                    {
                        foreach (var dev in logiList)
                        {
                            if (dev != null && (dev.IsConnected || dev.IsDonglePresent))
                            {
                                if (!tempConfigs.Exists(c => c.DeviceId == dev.DeviceId))
                                {
                                    var cfg = new CustomDeviceConfig
                                    {
                                        DeviceId = dev.DeviceId,
                                        OriginalName = dev.DeviceName,
                                        CustomName = resolveCustomName(dev.DeviceId, dev.DisplayName, dev.DeviceName),
                                        Category = resolveCategory(dev.DeviceId, dev.Category),
                                        Transport = dev.Transport ?? "Lightspeed 无线",
                                        CachedBattery = dev.BatteryPercent,
                                        HardwareFingerprint = dev.DeviceId
                                    };
                                    tempConfigs.Add(cfg);
                                }
                            }
                        }
                    }
                }
                catch { }



                // 2.56 Scan Valkyrie Devices (2.4G / USB)
                try
                {
                    var vkList = ValkyrieDeviceHelper.QueryAllValkyrieDevices();
                    if (vkList != null)
                    {
                        foreach (var vk in vkList)
                        {
                            if (vk != null && (vk.IsConnected || vk.IsDonglePresent))
                            {
                                if (!tempConfigs.Exists(c => c.DeviceId == vk.DeviceId || (!string.IsNullOrEmpty(c.HardwareFingerprint) && c.HardwareFingerprint == vk.HardwareFingerprint)))
                                {
                                    var cfg = new CustomDeviceConfig
                                    {
                                        DeviceId = vk.DeviceId,
                                        OriginalName = vk.DeviceName,
                                        CustomName = resolveCustomName(vk.DeviceId, vk.DisplayName, vk.DeviceName),
                                        Category = resolveCategory(vk.DeviceId, vk.Category),
                                        Transport = vk.Transport ?? "2.4G 无线",
                                        CachedBattery = vk.BatteryPercent,
                                        HardwareFingerprint = vk.HardwareFingerprint ?? vk.DeviceId
                                    };
                                    tempConfigs.Add(cfg);
                                }
                            }
                        }
                    }
                }
                catch { }

                // 2.57 Scan Universal Gaming Devices (OpenMouse / All-in-One: Lamzu, Pulsar, ATK, Attack Shark, etc.)
                try
                {
                    var gamingList = UniversalGamingDeviceHelper.QueryAllGamingDevices();
                    if (gamingList != null)
                    {
                        foreach (var dev in gamingList)
                        {
                            if (dev != null && (dev.IsConnected || dev.IsDonglePresent))
                            {
                                if (!tempConfigs.Exists(c => c.DeviceId == dev.DeviceId || (!string.IsNullOrEmpty(c.HardwareFingerprint) && c.HardwareFingerprint == dev.HardwareFingerprint)))
                                {
                                    var cfg = new CustomDeviceConfig
                                    {
                                        DeviceId = dev.DeviceId,
                                        OriginalName = dev.DeviceName,
                                        CustomName = resolveCustomName(dev.DeviceId, dev.DisplayName, dev.DeviceName),
                                        Category = resolveCategory(dev.DeviceId, dev.Category),
                                        Transport = dev.Transport ?? "2.4G 无线",
                                        CachedBattery = dev.BatteryPercent,
                                        HardwareFingerprint = dev.HardwareFingerprint ?? dev.DeviceId
                                    };
                                    tempConfigs.Add(cfg);
                                }
                            }
                        }
                    }
                }
                catch { }

                // 2.58 Scan Apple & Beats Devices
                try
                {
                    var appleList = AppleDeviceHelper.QueryAllAppleDevices();
                    if (appleList != null)
                    {
                        foreach (var dev in appleList)
                        {
                            if (dev != null && (dev.IsConnected || dev.IsDonglePresent))
                            {
                                if (!tempConfigs.Exists(c => c.DeviceId == dev.DeviceId || (!string.IsNullOrEmpty(c.HardwareFingerprint) && c.HardwareFingerprint == dev.HardwareFingerprint)))
                                {
                                    var cfg = new CustomDeviceConfig
                                    {
                                        DeviceId = dev.DeviceId,
                                        OriginalName = dev.DeviceName,
                                        CustomName = resolveCustomName(dev.DeviceId, dev.DisplayName, dev.DeviceName),
                                        Category = resolveCategory(dev.DeviceId, dev.Category),
                                        Transport = dev.Transport ?? "蓝牙",
                                        CachedBattery = dev.BatteryPercent,
                                        HardwareFingerprint = dev.HardwareFingerprint ?? dev.DeviceId
                                    };
                                    tempConfigs.Add(cfg);
                                }
                            }
                        }
                    }
                }
                catch { }

                // 2.6 Scan Generic HID Mice & Peripherals (2.4G / USB)
                try
                {
                    var genMice = GenericHidHelper.ScanGenericHidMice(existingIds);
                    foreach (var gm in genMice)
                    {
                        if (gm != null)
                        {
                            string gmKey = gm.DeviceId != null && gm.DeviceId.StartsWith("HID:") ? gm.DeviceId.Substring(4) : gm.DeviceId;
                            bool dup = tempConfigs.Exists(c => (c.DeviceId != null && c.DeviceId.IndexOf(gmKey, StringComparison.OrdinalIgnoreCase) >= 0) ||
                                                               (c.HardwareFingerprint != null && c.HardwareFingerprint.IndexOf(gmKey, StringComparison.OrdinalIgnoreCase) >= 0));
                            if (!dup)
                            {
                                tempConfigs.Add(gm);
                            }
                        }
                    }
                }
                catch { }

                // 3. Scan Bluetooth Devices (BLE & Classic)
                try
                {
                    var btList = BluetoothDeviceHelper.ScanAllBluetoothDevices();
                    foreach (var b in btList)
                    {
                        b.Transport = "蓝牙";
                        b.CustomName = resolveCustomName(b.DeviceId, b.CustomName, b.OriginalName);
                        b.Category = resolveCategory(b.DeviceId, b.Category);
                        tempConfigs.Add(b);
                    }
                }
                catch { }

                // Safely update UI atomically
                try
                {
                    if (this.IsDisposed) return;
                    this.BeginInvoke((Action)(() => {
                        if (this.IsDisposed) return;
                        isScanning = false;
                        beamControl.Stop();
                        btnScan.Enabled = true;
                        btnScan.Text = "🔄 重新扫描";

                        lstDevices.BeginUpdate();
                        try
                        {
                            lstDevices.Items.Clear();
                            scannedList.Clear();
                            scannedList.AddRange(tempConfigs);
                            for (int i = 0; i < scannedList.Count; i++)
                            {
                                string label = (!string.IsNullOrEmpty(scannedList[i].CustomName) && !string.Equals(scannedList[i].CustomName, scannedList[i].OriginalName, StringComparison.OrdinalIgnoreCase))
                                    ? scannedList[i].CustomName + " (" + scannedList[i].OriginalName + ")"
                                    : (!string.IsNullOrEmpty(scannedList[i].CustomName) ? scannedList[i].CustomName : scannedList[i].OriginalName);
                                lstDevices.Items.Add(label);
                            }
                        }
                        finally
                        {
                            lstDevices.EndUpdate();
                        }

                        if (lstDevices.Items.Count > 0)
                        {
                            lstDevices.SelectedIndex = 0;
                        }
                        else
                        {
                            lblTestStatus.ForeColor = Color.FromArgb(255, 183, 77);
                            lblTestStatus.Text = "● 未发现新的在线外设，请检查外设电源与配对状态。";
                        }
                    }));
                }
                catch { }
            });
        }

        private void OnDeviceSelected()
        {
            int idx = lstDevices.SelectedIndex;
            if (idx >= 0 && idx < scannedList.Count)
            {
                var item = scannedList[idx];
                bool isHidden = DeviceManager.IsDeviceHidden(item.DeviceId) || 
                                (!string.IsNullOrEmpty(item.HardwareFingerprint) && DeviceManager.IsDeviceHidden(item.HardwareFingerprint));
                bool already = false;
                if (!isHidden)
                {
                    var vList = DeviceManager.GetDeviceIdVariants(item.DeviceId);
                    if (!string.IsNullOrEmpty(item.HardwareFingerprint))
                    {
                        vList.AddRange(DeviceManager.GetDeviceIdVariants(item.HardwareFingerprint));
                    }
                    for (int vi = 0; vi < vList.Count; vi++)
                    {
                        if (existingIds.Contains(vList[vi]))
                        {
                            already = true;
                            break;
                        }
                    }
                }

                txtCustomName.Text = !string.IsNullOrEmpty(item.CustomName) ? item.CustomName : item.OriginalName;
                if (item.Category == DeviceCategory.Mouse) cmbCategory.SelectedIndex = 0;
                else if (item.Category == DeviceCategory.Keyboard) cmbCategory.SelectedIndex = 1;
                else if (item.Category == DeviceCategory.Headset) cmbCategory.SelectedIndex = 2;
                else if (item.Category == DeviceCategory.Earbuds) cmbCategory.SelectedIndex = 3;
                else if (item.Category == DeviceCategory.Gamepad) cmbCategory.SelectedIndex = 4;
                else if (item.Category == DeviceCategory.Dongle) cmbCategory.SelectedIndex = 5;
                else cmbCategory.SelectedIndex = 6;

                if (already)
                {
                    lblTestStatus.ForeColor = Color.FromArgb(0, 230, 118);
                    lblTestStatus.Text = "● 该设备已在设备库中，您可以直接修改自定义昵称或分类并保存更新。";
                    btnSave.Text = "💾 保存修改";
                    btnSave.NormalColor = Color.FromArgb(0, 180, 90);
                    btnSave.HoverColor = Color.FromArgb(0, 210, 110);
                    btnSave.Enabled = true;
                }
                else
                {
                    lblTestStatus.ForeColor = Color.FromArgb(0, 230, 118);
                    string battStr = item.CachedBattery > 0 ? string.Format("实时电量: {0}%", item.CachedBattery) : "供电: USB/免驱";
                    lblTestStatus.Text = string.Format("● 设备在线就绪！{0}\n连接通道: {1} | 标识: {2}", 
                        battStr, item.Transport ?? "2.4G/USB", item.HardwareFingerprint ?? item.DeviceId);
                    btnSave.Text = "➕ 加入监控";
                    btnSave.NormalColor = Color.FromArgb(0, 200, 83);
                    btnSave.HoverColor = Color.FromArgb(0, 230, 118);
                    btnSave.Enabled = true;
                }
            }
            else
            {
                btnSave.Enabled = false;
            }
        }

        private void SaveSelectedDevice()
        {
            int idx = lstDevices.SelectedIndex;
            if (idx >= 0 && idx < scannedList.Count)
            {
                var item = scannedList[idx];
                string name = txtCustomName.Text.Trim();
                if (string.IsNullOrEmpty(name)) name = !string.IsNullOrEmpty(item.CustomName) ? item.CustomName : item.OriginalName;
                item.CustomName = name;

                switch (cmbCategory.SelectedIndex)
                {
                    case 0: item.Category = DeviceCategory.Mouse; break;
                    case 1: item.Category = DeviceCategory.Keyboard; break;
                    case 2: item.Category = DeviceCategory.Headset; break;
                    case 3: item.Category = DeviceCategory.Earbuds; break;
                    case 4: item.Category = DeviceCategory.Gamepad; break;
                    case 5: item.Category = DeviceCategory.Dongle; break;
                    default: item.Category = DeviceCategory.Generic; break;
                }

                // Ensure canonical ID for Razer devices
                if (item.DeviceId.StartsWith("Razer:1532:", StringComparison.OrdinalIgnoreCase))
                {
                    item.DeviceId = RazerDeviceHelper.NormalizeRazerDeviceId(item.DeviceId);
                }

                DeviceManager.SaveCustomDevice(item);
                DeviceManager.UnhideDevice(item.DeviceId);
                if (!string.IsNullOrEmpty(item.HardwareFingerprint)) DeviceManager.UnhideDevice(item.HardwareFingerprint);
                if (item.DeviceId.StartsWith("Razer:1532:", StringComparison.OrdinalIgnoreCase))
                {
                    string norm = RazerDeviceHelper.NormalizeRazerDeviceId(item.DeviceId);
                    DeviceManager.UnhideDevice(norm);
                }

                // Also append to priority list if not in it
                var prio = DeviceManager.GetPriorityList();
                if (!prio.Contains(item.DeviceId))
                {
                    prio.Add(item.DeviceId);
                    DeviceManager.SavePriorityList(prio);
                }

                this.AddedDeviceId = item.DeviceId;
                this.DialogResult = DialogResult.OK;
                this.Close();
            }
        }

        public static string GetAiAdaptationPrompt()
        {
            return @"# 任务：为开源软件「FerrisPulse (灵脉)」专属适配我正在使用的硬件外设

你好！我现在使用的外设设备暂未被「FerrisPulse (灵脉)」原生识别。请你作为专业的系统级硬件逆向与 C# 智能体工程师，帮助我完成当前电脑上连接设备的电量监控与性能适配。

## ⚠️ 第 1 步必读：继承工程经验（杜绝踩坑）
在动工编写任何代码之前，必须首先通读工程根目录下的 `docs/AGENT_HANDBOOK.md` 与 `AGENT_RULES.md`！
本项目前序 AI 智能体已经沉淀了 11 大底层铁律与血泪经验（包括严格 C# 5.0 / .NET 4.0 语法基准、Win32 键盘 HID 0 权限握手、DWM 原生窗口抗白框状态机、测试全内存反射防句柄锁死等）。请务必全盘继承前序经验，切勿重复踩坑！

## 2. 获取工程源码
请使用 git 从以下官方仓库克隆最新完整源码：
- GitHub (首选): https://github.com/Ferris-echo/FerrisPulse.git
- Gitee (镜像): https://gitee.com/Ferris-echo/ferris-pulse.git

## 3. 探测我当前物理连接的硬件设备
请利用你的系统工具（如 PowerShell / Win32 SetupAPI / HID 接口查询等），自动检索我当前电脑接入的外设：
1. 找出未被识别外设的 Vendor ID (VID)、Product ID (PID)、Usage / UsagePage 以及设备完整物理路径。
2. 识别该外设的产品品牌、型号与连接形态（2.4G 接收器 / 蓝牙 BLE / 有线 USB）。

## 4. 逆向与通信协议检索（发挥你的联网能力）
请通过联网检索、开源社区逆向成果（如 OpenRGB、libratbag、Linux 内核驱动源码、hidapi、抓包分析等）查询该型号的私有通信报文：
- 核心目标（必选）：实现精准电池电量读取（Battery Level 0-100%）与充电状态识别。
- 扩展目标（如果是鼠标）：探测并尝试实现 DPI 档位读取/设置、X/Y 轴独立双轴调节、以及回报率（Hz）切换指令。

## 5. 遵守项目的开发铁律与架构规范
代码实现必须严格遵循：
1. 编译器基准：严格使用 C# 5.0 语法（严禁使用 C# 6.0+ 语法，如 $""...""、?.、nameof），必须能够使用系统自带 csc.exe 通过根目录的 build.bat 零报错编译。
2. 零外部依赖：仅允许引用 .NET 4.0 核心程序集，通信采用 Win32 HID P/Invoke，严禁引入 NuGet 包或第三方 DLL。
3. 文件编码安全：所有新建或修改的源码文件必须严格保存为【UTF-8 with BOM】签名。
4. 模块化落位：
   - 若为已存在品牌（如 Razer, Logitech, Rapoo, Valkyrie 等）：在 src/Hardware/<Brand>DeviceHelper.cs 中增加该型号的识别与报文解析。
   - 若为全新品牌：在 src/Hardware/ 下新建 <Brand>DeviceHelper.cs，并在 src/Hardware/DeviceManager.cs 中统一注册接入。
   - 适配完成后，设备分类、电量与支持的特性无缝对接到主界面 UI（MainForm）与 OSD。

## 6. 本地编译与回归测试验证
在源码根目录下执行 cmd.exe /c ""build.bat"" 验证编译是否成功生成 FerrisPulse.exe，并运行相关自动化测试确保没有回归问题。

## 7. 引导我向作者贡献代码（开源知识飞轮）
适配成功并完成实测后，请为我整理一份简洁的贡献摘要（包含修改了哪些文件、适配了什么型号、设备 VID/PID 与报文细节），并引导我通过以下途径之一分享给作者合并入官方主线：
- 方式 A：提交 GitHub Pull Request / Issue (https://github.com/Ferris-echo/FerrisPulse)
- 方式 B：提交 Gitee Pull Request / Issue (https://gitee.com/Ferris-echo/ferris-pulse)
- 方式 C：将代码变更或 patch 文件通过邮件/文本形式共享给作者
作者会将你的适配成果永久纳入官方支持库，并在更新日志（CHANGELOG）与关于页面中为你署名致谢！";
        }
    }
}
