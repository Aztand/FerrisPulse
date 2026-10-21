// ============================================================================
// 模块名称: SonyInzoneHelper.cs
// 所属区域: Hardware (硬件驱动层)
// 核心职责:
//   索尼 (Sony) INZONE Buds (WF-G700N) 2.4GHz 无线游戏入耳式耳机私有 HID 协议适配：
//   0xFF04 Vendor HID 接口、Report ID 0x02、64 字节 Output/Input 报告交互、
//   双耳与充电盒独立电量解析及校验和核验。
// 依赖关系: HidTransport.cs, MouseBatteryInfo.cs
//
// ⚠️ AI 维护准则 (AI MAINTENANCE DIRECTIVE - DO NOT REMOVE) ⚠️:
// 1. [契约同步更新]: 修改帧格式、电量解析或设备识别时必须同步更新上方说明。
// 2. [C# 5 兼容铁律]: 严禁使用 C# 6+ 语法（禁止字符串插值、空条件运算符、nameof）。
// 3. [编码格式锁定]: 本文件必须严格保存为【UTF-8 with BOM】编码。
// ============================================================================

using System;
using System.Collections.Generic;

namespace RazerBatteryTray
{
    public class SonyInzoneBudsState
    {
        public int LeftBattery;      // -1 表示盒内/离线
        public bool LeftCharging;
        public int RightBattery;     // -1 表示盒内/离线
        public bool RightCharging;
        public int CaseBattery;      // -1 表示不可用
        public bool CaseCharging;
        public bool IsConnected;

        public SonyInzoneBudsState()
        {
            LeftBattery = -1;
            RightBattery = -1;
            CaseBattery = -1;
            LeftCharging = false;
            RightCharging = false;
            CaseCharging = false;
            IsConnected = false;
        }
    }

    public static class SonyInzoneHelper
    {
        private static readonly object hidLock = new object();

        public const int VendorIdSony = 0x054C;
        public const int PidInzoneBuds = 0x0EC2;

        public const int TargetUsagePage = 0xFF04;
        public const int TargetUsage = 0x0001;
        public const byte ReportId = 0x02;
        public const int ReportLength = 64;

        private const int ReadTimeoutMs = 500;
        private const int QueryThrottleMs = 1000;

        private static ushort sequenceCounter = 1;
        private static DateTime lastQueryTime = DateTime.MinValue;
        private static List<MouseBatteryInfo> cachedDevices = new List<MouseBatteryInfo>();

        public static bool IsSupportedVidPid(int vid, int pid)
        {
            return vid == VendorIdSony && pid == PidInzoneBuds;
        }

        public static bool IsSonyInzoneDevice(string identifier)
        {
            if (string.IsNullOrEmpty(identifier)) return false;
            string lower = identifier.ToLowerInvariant();
            bool isSonyVid = lower.Contains("vid_054c") || lower.Contains("054c:") || lower.Contains("054c&");
            if (!isSonyVid) return false;
            return lower.Contains("pid_0ec2") || lower.Contains(":0ec2");
        }

        public static byte CalculateQueryChecksum(byte seqLo, byte seqHi)
        {
            int sum = 0x96 + 0xC3 + 0x41 + 0x04 + 0x01 + seqLo + seqHi;
            return (byte)(sum & 0xFF);
        }

        public static byte[] BuildQueryPacket(ushort sequence)
        {
            byte[] packet = new byte[ReportLength];
            packet[0] = ReportId; // 0x02
            packet[1] = 0x0C;     // Payload length = 12 bytes
            packet[2] = 0x01;
            packet[3] = 0x00;
            packet[4] = 0xFC;
            packet[5] = 0x08;
            packet[6] = 0x96;
            packet[7] = 0xC3;
            packet[8] = 0x41;
            packet[9] = 0x04;
            packet[10] = 0x01;
            byte seqLo = (byte)(sequence & 0xFF);
            byte seqHi = (byte)((sequence >> 8) & 0xFF);
            packet[11] = seqLo;
            packet[12] = seqHi;
            packet[13] = CalculateQueryChecksum(seqLo, seqHi);
            return packet;
        }

        public static byte CalculateResponseChecksum(byte[] buffer, int offset, int length)
        {
            if (buffer == null || offset < 0 || length <= 0 || offset + length > buffer.Length)
            {
                return 0;
            }

            int sum = 0;
            for (int i = 0; i < length; i++)
            {
                sum += buffer[offset + i];
            }
            return (byte)(sum & 0xFF);
        }

        public static bool ParseBatteryResponse(byte[] buffer, out SonyInzoneBudsState state)
        {
            state = new SonyInzoneBudsState();
            if (buffer == null || buffer.Length < 20)
            {
                return false;
            }

            // 报文结构校验: Report ID == 0x02, Header[6..7] == 0x96 0xC3, Header[8] == 0x14
            if (buffer[0] != ReportId || buffer[6] != 0x96 || buffer[7] != 0xC3)
            {
                return false;
            }

            // 校验和核验: sum(buffer[6..18]) ≡ buffer[19]
            byte calculatedChecksum = CalculateResponseChecksum(buffer, 6, 13);
            if (buffer[19] != calculatedChecksum)
            {
                return false;
            }

            byte lStat = buffer[13];
            byte lBatt = buffer[14];
            byte rStat = buffer[15];
            byte rBatt = buffer[16];
            byte cStat = buffer[17];
            byte cBatt = buffer[18];

            state.LeftBattery = (lBatt <= 100) ? (int)lBatt : -1;
            state.LeftCharging = (lStat == 0x01);

            state.RightBattery = (rBatt <= 100) ? (int)rBatt : -1;
            state.RightCharging = (rStat == 0x01);

            state.CaseBattery = (cBatt <= 100) ? (int)cBatt : -1;
            state.CaseCharging = (cStat == 0x01);

            state.IsConnected = (state.LeftBattery >= 0 || state.RightBattery >= 0 || state.CaseBattery >= 0);
            return true;
        }

        public static string BuildTooltip(SonyInzoneBudsState state)
        {
            if (state == null || !state.IsConnected)
            {
                return "耳塞在充电盒内休眠 (2.4G 接收器在线)";
            }

            List<string> parts = new List<string>();
            if (state.LeftBattery >= 0)
            {
                parts.Add(string.Format("左耳: {0}%{1}", state.LeftBattery, state.LeftCharging ? "⚡" : ""));
            }
            if (state.RightBattery >= 0)
            {
                parts.Add(string.Format("右耳: {0}%{1}", state.RightBattery, state.RightCharging ? "⚡" : ""));
            }
            if (state.CaseBattery >= 0)
            {
                parts.Add(string.Format("充电盒: {0}%{1}", state.CaseBattery, state.CaseCharging ? "⚡" : ""));
            }

            if (parts.Count == 0)
            {
                return "耳塞在充电盒内休眠";
            }
            return string.Join(" | ", parts.ToArray());
        }

        public static int ResolvePrimaryBatteryPercent(SonyInzoneBudsState state)
        {
            if (state == null) return -1;
            if (state.LeftBattery >= 0 && state.RightBattery >= 0)
            {
                return Math.Min(state.LeftBattery, state.RightBattery);
            }
            if (state.LeftBattery >= 0) return state.LeftBattery;
            if (state.RightBattery >= 0) return state.RightBattery;
            if (state.CaseBattery >= 0) return state.CaseBattery;
            return -1;
        }

        public static List<MouseBatteryInfo> QueryAllSonyInzoneDevices()
        {
            lock (hidLock)
            {
                DateTime now = DateTime.Now;
                if ((now - lastQueryTime).TotalMilliseconds < QueryThrottleMs && cachedDevices.Count > 0)
                {
                    return new List<MouseBatteryInfo>(cachedDevices);
                }

                List<MouseBatteryInfo> result = new List<MouseBatteryInfo>();
                try
                {
                    List<HidDeviceDescriptor> descriptors = HidTransport.Enumerate(VendorIdSony, PidInzoneBuds);
                    if (descriptors == null || descriptors.Count == 0)
                    {
                        cachedDevices = result;
                        lastQueryTime = now;
                        return result;
                    }

                    // 寻找匹配 TargetUsagePage 0xFF04 与 TargetUsage 0x0001 的通讯集合
                    HidDeviceDescriptor targetDescriptor = null;
                    for (int i = 0; i < descriptors.Count; i++)
                    {
                        var d = descriptors[i];
                        if (d.UsagePage == TargetUsagePage && d.Usage == TargetUsage)
                        {
                            targetDescriptor = d;
                            break;
                        }
                    }

                    // 宽松回退：匹配 OutputReportLength == 64
                    if (targetDescriptor == null)
                    {
                        for (int i = 0; i < descriptors.Count; i++)
                        {
                            if (descriptors[i].OutputReportLength == ReportLength)
                            {
                                targetDescriptor = descriptors[i];
                                break;
                            }
                        }
                    }

                    if (targetDescriptor == null)
                    {
                        targetDescriptor = descriptors[0];
                    }

                    IntPtr handle = HidTransport.Open(targetDescriptor.DevicePath);
                    if (!HidTransport.IsValidHandle(handle))
                    {
                        // 接收器句柄无法打开，生成占位离线设备
                        MouseBatteryInfo placeholder = CreatePlaceholderDevice(targetDescriptor);
                        result.Add(placeholder);
                        cachedDevices = result;
                        lastQueryTime = now;
                        return result;
                    }

                    SonyInzoneBudsState state = null;
                    try
                    {
                        HidTransport.DrainReports(handle, ReportLength, 3);

                        ushort seq = sequenceCounter++;
                        if (sequenceCounter == 0) sequenceCounter = 1;

                        byte[] queryPacket = BuildQueryPacket(seq);
                        bool wrote = HidTransport.WriteReport(handle, queryPacket, queryPacket.Length, ReadTimeoutMs);

                        if (wrote)
                        {
                            byte[] resp;
                            bool readOk = HidTransport.ReadReport(handle, ReportLength, ReadTimeoutMs, out resp);
                            if (readOk && resp != null)
                            {
                                SonyInzoneBudsState parsedState;
                                if (ParseBatteryResponse(resp, out parsedState))
                                {
                                    state = parsedState;
                                }
                            }
                        }
                    }
                    finally
                    {
                        HidTransport.Close(handle);
                    }

                    MouseBatteryInfo dev = CreateDeviceFromState(targetDescriptor, state);
                    result.Add(dev);
                    cachedDevices = result;
                    lastQueryTime = now;
                    return result;
                }
                catch
                {
                    return result;
                }
            }
        }

        private static MouseBatteryInfo CreatePlaceholderDevice(HidDeviceDescriptor desc)
        {
            MouseBatteryInfo info = new MouseBatteryInfo();
            info.DeviceId = "Sony:054C:0EC2";
            info.Brand = "Sony";
            info.Category = DeviceCategory.Earbuds;
            info.DeviceName = "Sony INZONE Buds (WF-G700N)";
            info.CustomName = "INZONE Buds";
            info.Transport = "2.4G 无线";
            info.IsDonglePresent = true;
            info.IsConnected = false;
            info.IsSleeping = true;
            info.BatteryPercent = -1;
            info.CustomTooltip = "耳塞在充电盒内休眠 (2.4G 接收器在线)";
            info.HardwareId = "HID\\VID_054C&PID_0EC2";
            info.HardwareFingerprint = "Sony:054C:0EC2:Buds";
            info.LastUpdated = DateTime.Now;
            return info;
        }

        private static MouseBatteryInfo CreateDeviceFromState(HidDeviceDescriptor desc, SonyInzoneBudsState state)
        {
            MouseBatteryInfo info = CreatePlaceholderDevice(desc);
            if (state == null)
            {
                return info;
            }

            info.IsConnected = state.IsConnected;
            info.IsSleeping = !state.IsConnected;
            info.BatteryPercent = ResolvePrimaryBatteryPercent(state);
            info.IsCharging = state.LeftCharging || state.RightCharging || state.CaseCharging;
            info.CustomTooltip = BuildTooltip(state);
            info.LastUpdated = DateTime.Now;
            return info;
        }
    }
}
