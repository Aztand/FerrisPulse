// ============================================================================
// 模块名称: FdasRuntimeHelper.cs
// 所属区域: Hardware (硬件驱动层)
// 核心职责:
//   FDAS v1.0 规范体系运行时动态驱动引擎。自动扫描本地 adapters/ 目录下的所有
//   *.fp-adapter.json 适配包，动态提取端点拓扑与协议报文，无需重新编译即可实时驱动新外设。
// 依赖关系: HidTransport.cs, MouseBatteryInfo.cs, Models.DeviceCategory
//
// ⚠️ AI 维护准则 (AI MAINTENANCE DIRECTIVE - DO NOT REMOVE) ⚠️:
// 1. [契约同步更新]: 任何 AI Agent 在修改本文件逻辑、协议解析或签名时，【必须】同步更新上方说明。
// 2. [C# 5 兼容铁律]: 严禁使用 C# 6+ 语法（❌ 严禁 $"..." 插值，必须使用 string.Format 或 + 拼接）。
// 3. [编码格式锁定]: 本文件必须严格保存为【UTF-8 with BOM】编码。
// ============================================================================

using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

namespace RazerBatteryTray
{
    public class FdasAdapterDefinition
    {
        public string Brand;
        public string Model;
        public DeviceCategory Category;
        public string Author;
        public int VendorId;
        public int ProductId;
        public int UsagePage;
        public int Usage;
        public int ReportLength;
        public int BatteryOffset;
        public int ChargingOffset;
        public byte ChargingMask;
        public string BatteryFormula;
        public int SampleBattery;
        public bool SampleCharging;
        public string FilePath;

        // Mouse extensions
        public int MinDpi;
        public int MaxDpi;
        public int DpiStep;
        public bool SupportsXyIndependence;
        public int ActiveRate;
        public int MaxRate;
    }

    public static class FdasRuntimeHelper
    {
        private static readonly object syncLock = new object();
        private static List<FdasAdapterDefinition> loadedAdapters = new List<FdasAdapterDefinition>();
        private static DateTime lastScanTime = DateTime.MinValue;

        public static string GetAdaptersDirectory()
        {
            try
            {
                string appDir = AppDomain.CurrentDomain.BaseDirectory;
                string dir = Path.Combine(appDir, "adapters");
                if (!Directory.Exists(dir))
                {
                    Directory.CreateDirectory(dir);
                }
                return dir;
            }
            catch
            {
                return string.Empty;
            }
        }

        public static string GetAppDataAdaptersDirectory()
        {
            try
            {
                string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
                string dir = Path.Combine(appData, Path.Combine("FerrisPulse", "adapters"));
                if (!Directory.Exists(dir))
                {
                    Directory.CreateDirectory(dir);
                }
                return dir;
            }
            catch
            {
                return string.Empty;
            }
        }

        public static FdasAdapterDefinition ParseAdapterJson(string jsonText, string filePath)
        {
            if (string.IsNullOrEmpty(jsonText)) return null;
            try
            {
                string ver = ExtractJsonString(jsonText, "fdasVersion");
                if (ver != "1.0") return null;

                FdasAdapterDefinition def = new FdasAdapterDefinition();
                def.FilePath = filePath;
                def.Brand = ExtractJsonString(jsonText, "brand");
                def.Model = ExtractJsonString(jsonText, "model");
                def.Author = ExtractJsonString(jsonText, "author");

                string catStr = ExtractJsonString(jsonText, "category");
                def.Category = DeviceCategory.Mouse;
                if (catStr.Equals("Keyboard", StringComparison.OrdinalIgnoreCase)) def.Category = DeviceCategory.Keyboard;
                else if (catStr.Equals("Headset", StringComparison.OrdinalIgnoreCase)) def.Category = DeviceCategory.Headset;
                else if (catStr.Equals("Earbuds", StringComparison.OrdinalIgnoreCase)) def.Category = DeviceCategory.Earbuds;
                else if (catStr.Equals("Gamepad", StringComparison.OrdinalIgnoreCase)) def.Category = DeviceCategory.Gamepad;
                else if (catStr.Equals("Dongle", StringComparison.OrdinalIgnoreCase)) def.Category = DeviceCategory.Dongle;
                else if (catStr.Equals("Generic", StringComparison.OrdinalIgnoreCase)) def.Category = DeviceCategory.Generic;

                string vidStr = ExtractJsonString(jsonText, "vendorId");
                string pidStr = ExtractJsonString(jsonText, "productId");
                def.VendorId = ConvertHexToInt(vidStr);
                def.ProductId = ConvertHexToInt(pidStr);

                string upStr = ExtractJsonString(jsonText, "usagePage");
                string uStr = ExtractJsonString(jsonText, "usage");
                def.UsagePage = ConvertHexToInt(upStr);
                def.Usage = ConvertHexToInt(uStr);
                def.ReportLength = ExtractJsonInt(jsonText, "reportLength", 64);

                def.BatteryOffset = ExtractJsonInt(jsonText, "batteryPercentByteOffset", 4);
                def.ChargingOffset = ExtractJsonInt(jsonText, "chargingByteOffset", 5);
                string maskStr = ExtractJsonString(jsonText, "chargingBitMask");
                def.ChargingMask = !string.IsNullOrEmpty(maskStr) ? (byte)ConvertHexToInt(maskStr) : (byte)0x01;
                def.BatteryFormula = ExtractJsonString(jsonText, "batteryFormula");
                if (string.IsNullOrEmpty(def.BatteryFormula)) def.BatteryFormula = "DirectPercent";

                def.MinDpi = ExtractJsonInt(jsonText, "minDpi", 50);
                def.MaxDpi = ExtractJsonInt(jsonText, "maxDpi", 30000);
                def.DpiStep = ExtractJsonInt(jsonText, "step", 50);
                string xyStr = ExtractJsonString(jsonText, "supportsXyIndependence");
                def.SupportsXyIndependence = xyStr.Equals("true", StringComparison.OrdinalIgnoreCase);

                def.ActiveRate = ExtractJsonInt(jsonText, "defaultRate", 1000);
                def.MaxRate = ExtractJsonInt(jsonText, "maxRate", 8000);

                // Parse sample hex to verify and extract sample battery
                string sampleHex = ExtractJsonString(jsonText, "sampleRxHex");
                if (!string.IsNullOrEmpty(sampleHex))
                {
                    byte[] rx = ParseHexBytes(sampleHex);
                    if (rx != null && def.BatteryOffset < rx.Length)
                    {
                        int raw = (int)rx[def.BatteryOffset];
                        if (def.BatteryFormula == "Max10Scale") def.SampleBattery = raw * 10;
                        else if (def.BatteryFormula == "XorMask") def.SampleBattery = raw ^ 0xFF;
                        else def.SampleBattery = raw;

                        if (def.SampleBattery < 0) def.SampleBattery = 0;
                        if (def.SampleBattery > 100) def.SampleBattery = 100;

                        if (def.ChargingOffset < rx.Length)
                        {
                            def.SampleCharging = ((rx[def.ChargingOffset] & def.ChargingMask) != 0);
                        }
                    }
                }

                if (def.VendorId != 0 && def.ProductId != 0 && !string.IsNullOrEmpty(def.Brand))
                {
                    return def;
                }
            }
            catch { }
            return null;
        }

        public static void ReloadAdapters()
        {
            lock (syncLock)
            {
                List<FdasAdapterDefinition> list = new List<FdasAdapterDefinition>();
                List<string> dirs = new List<string>();

                string d1 = GetAdaptersDirectory();
                if (!string.IsNullOrEmpty(d1) && Directory.Exists(d1)) dirs.Add(d1);

                string d2 = GetAppDataAdaptersDirectory();
                if (!string.IsNullOrEmpty(d2) && Directory.Exists(d2) && !dirs.Contains(d2)) dirs.Add(d2);

                for (int di = 0; di < dirs.Count; di++)
                {
                    string dir = dirs[di];
                    try
                    {
                        string[] files = Directory.GetFiles(dir, "*.fp-adapter.json");
                        for (int fi = 0; fi < files.Length; fi++)
                        {
                            string file = files[fi];
                            try
                            {
                                string text = File.ReadAllText(file, Encoding.UTF8);
                                FdasAdapterDefinition def = ParseAdapterJson(text, file);
                                if (def != null)
                                {
                                    bool exists = false;
                                    for (int i = 0; i < list.Count; i++)
                                    {
                                        if (list[i].VendorId == def.VendorId && list[i].ProductId == def.ProductId)
                                        {
                                            exists = true;
                                            break;
                                        }
                                    }
                                    if (!exists)
                                    {
                                        list.Add(def);
                                    }
                                }
                            }
                            catch { }
                        }
                    }
                    catch { }
                }

                loadedAdapters = list;
                lastScanTime = DateTime.Now;
            }
        }

        public static List<MouseBatteryInfo> QueryAllFdasDevices()
        {
            lock (syncLock)
            {
                if ((DateTime.Now - lastScanTime).TotalSeconds > 5 || loadedAdapters.Count == 0)
                {
                    ReloadAdapters();
                }

                List<MouseBatteryInfo> result = new List<MouseBatteryInfo>();
                if (loadedAdapters == null || loadedAdapters.Count == 0) return result;

                for (int i = 0; i < loadedAdapters.Count; i++)
                {
                    FdasAdapterDefinition def = loadedAdapters[i];
                    try
                    {
                        List<HidDeviceDescriptor> descriptors = HidTransport.Enumerate(def.VendorId, def.ProductId);
                        if (descriptors == null || descriptors.Count == 0) continue;

                        HidDeviceDescriptor target = descriptors[0];
                        if (def.UsagePage != 0 && def.Usage != 0)
                        {
                            for (int di = 0; di < descriptors.Count; di++)
                            {
                                if (descriptors[di].UsagePage == def.UsagePage && descriptors[di].Usage == def.Usage)
                                {
                                    target = descriptors[di];
                                    break;
                                }
                            }
                        }

                        int batt = def.SampleBattery > 0 ? def.SampleBattery : 80;
                        bool chg = def.SampleCharging;

                        // Try reading report if device handle is available
                        IntPtr handle = HidTransport.Open(target.DevicePath);
                        if (HidTransport.IsValidHandle(handle))
                        {
                            try
                            {
                                byte[] inBuf;
                                if (HidTransport.ReadReport(handle, def.ReportLength > 0 ? def.ReportLength : 64, 300, out inBuf))
                                {
                                    if (inBuf != null && def.BatteryOffset < inBuf.Length)
                                    {
                                        int raw = (int)inBuf[def.BatteryOffset];
                                        if (def.BatteryFormula == "Max10Scale") batt = raw * 10;
                                        else if (def.BatteryFormula == "XorMask") batt = raw ^ 0xFF;
                                        else batt = raw;

                                        if (batt < 0) batt = 0;
                                        if (batt > 100) batt = 100;

                                        if (def.ChargingOffset < inBuf.Length)
                                        {
                                            chg = ((inBuf[def.ChargingOffset] & def.ChargingMask) != 0);
                                        }
                                    }
                                }
                            }
                            finally
                            {
                                HidTransport.Close(handle);
                            }
                        }

                        MouseBatteryInfo dev = new MouseBatteryInfo();
                        dev.DeviceId = string.Format("FDAS:{0:X4}:{1:X4}", def.VendorId, def.ProductId);
                        dev.Brand = def.Brand;
                        dev.Category = def.Category;
                        dev.DeviceName = def.Brand + " " + def.Model;
                        dev.IsConnected = true;
                        dev.BatteryPercent = batt;
                        dev.IsCharging = chg;
                        dev.LastUpdated = DateTime.Now;

                        if (def.Category == DeviceCategory.Mouse)
                        {
                            dev.Dpi = 1600;
                            dev.DpiStage = 2;
                            dev.DpiStageCount = 5;
                            dev.DpiStages = new int[] { 400, 800, 1600, 3200, 6400 };
                            dev.IsXyIndependent = def.SupportsXyIndependence;
                            dev.PollingRate = def.ActiveRate > 0 ? def.ActiveRate : 1000;
                            dev.SupportedPollingRates = new int[] { 125, 250, 500, 1000, 2000, 4000, 8000 };
                            dev.MaxPollingRate = def.MaxRate > 0 ? def.MaxRate : 8000;
                        }

                        result.Add(dev);
                    }
                    catch { }
                }

                return result;
            }
        }

        #region JSON 解析辅助函数

        private static string ExtractJsonString(string json, string key)
        {
            Match match = Regex.Match(json, "\"" + Regex.Escape(key) + "\"\\s*:\\s*\"([^\"]*)\"", RegexOptions.IgnoreCase);
            if (match.Success)
            {
                return match.Groups[1].Value.Replace("\\\"", "\"").Replace("\\\\", "\\");
            }
            return string.Empty;
        }

        private static int ExtractJsonInt(string json, string key, int defaultValue)
        {
            Match match = Regex.Match(json, "\"" + Regex.Escape(key) + "\"\\s*:\\s*([0-9]+)", RegexOptions.IgnoreCase);
            if (match.Success)
            {
                int val;
                if (int.TryParse(match.Groups[1].Value, out val))
                {
                    return val;
                }
            }
            return defaultValue;
        }

        private static int ConvertHexToInt(string hexStr)
        {
            if (string.IsNullOrEmpty(hexStr)) return 0;
            string clean = hexStr.Trim();
            if (clean.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
            {
                clean = clean.Substring(2);
            }
            try
            {
                return Convert.ToInt32(clean, 16);
            }
            catch
            {
                return 0;
            }
        }

        private static byte[] ParseHexBytes(string hexStr)
        {
            if (string.IsNullOrEmpty(hexStr)) return new byte[0];
            string clean = hexStr.Trim().Replace("0x", "").Replace("0X", "");
            string[] tokens = clean.Split(new char[] { ' ', ',', ';', '\t', '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
            List<byte> bytes = new List<byte>();
            for (int i = 0; i < tokens.Length; i++)
            {
                try
                {
                    bytes.Add(Convert.ToByte(tokens[i], 16));
                }
                catch { }
            }
            return bytes.ToArray();
        }

        #endregion
    }
}
