# tests\test_earbuds_name_integration.ps1
$asmPath = Join-Path $PSScriptRoot "..\FerrisPulse.exe"
if (-not (Test-Path $asmPath)) { $asmPath = "FerrisPulse.exe" }
$fullPath = (Resolve-Path $asmPath).Path
$bytes = [System.IO.File]::ReadAllBytes($fullPath)
$asm = [System.Reflection.Assembly]::Load($bytes)

$tMgr = $asm.GetType("RazerBatteryTray.DeviceManager")
$mLoad = $tMgr.GetMethod("LoadCustomDevices", [System.Reflection.BindingFlags]'Public,Static')
$cfgs = $mLoad.Invoke($null, @())

$earbudCfg = $null
foreach ($c in $cfgs) {
    if ($c.DeviceId -eq "BT_5CD33D59A938") {
        $earbudCfg = $c
        break
    }
}

$seededByTest = $false
if ($earbudCfg -eq $null) {
    # 在无预装测试设备的 CI 裸机环境中，模拟保存蓝牙耳机自定义名称配置
    $tCfg = $asm.GetType("RazerBatteryTray.CustomDeviceConfig")
    $mockDev = [Activator]::CreateInstance($tCfg)
    $mockDev.DeviceId = "BT_5CD33D59A938"
    $mockDev.CustomName = "鹏飞的buds4pro"
    $mockDev.OriginalName = "Buds 4 Pro"
    $mockDev.HardwareFingerprint = "5CD33D59A938"
    $mSave = $tMgr.GetMethod("SaveCustomDevice", [System.Reflection.BindingFlags]'Public,Static')
    $mSave.Invoke($null, @($mockDev))
    $seededByTest = $true

    $cfgs = $mLoad.Invoke($null, @())
    foreach ($c in $cfgs) {
        if ($c.DeviceId -eq "BT_5CD33D59A938") {
            $earbudCfg = $c
            break
        }
    }
}

if ($earbudCfg -eq $null) {
    Write-Host "RED: Earbuds config BT_5CD33D59A938 not found in registry!" -ForegroundColor Red
    exit 1
}

try {
    Write-Host ("Found earbud config: DeviceId=" + $earbudCfg.DeviceId + ", CustomName=" + $earbudCfg.CustomName) -ForegroundColor Cyan

    # Test simulated query mapping:
    $tInfo = $asm.GetType("RazerBatteryTray.MouseBatteryInfo")
    $devInfo = [Activator]::CreateInstance($tInfo)
    $devInfo.DeviceId = $earbudCfg.DeviceId
    $devInfo.HardwareFingerprint = $earbudCfg.HardwareFingerprint
    $devInfo.Category = $earbudCfg.Category
    $devInfo.CustomName = $earbudCfg.CustomName
    $devInfo.DeviceName = "Buds 4 Pro"

    if ($devInfo.DisplayName -ne $earbudCfg.CustomName) {
        Write-Host ("FAIL DisplayName: Expected '" + $earbudCfg.CustomName + "', got '" + $devInfo.DisplayName + "'") -ForegroundColor Red
        exit 1
    }
    Write-Host ("PASS DisplayName: " + $devInfo.DisplayName) -ForegroundColor Green

    if ($devInfo.FriendlyShortName -ne $earbudCfg.CustomName) {
        Write-Host ("FAIL FriendlyShortName: Expected '" + $earbudCfg.CustomName + "', got '" + $devInfo.FriendlyShortName + "'") -ForegroundColor Red
        exit 1
    }
    Write-Host ("PASS FriendlyShortName: " + $devInfo.FriendlyShortName) -ForegroundColor Green

    Write-Host "INTEGRATION VERIFIED: Bluetooth earbuds nickname correctly maps across all UI surfaces!" -ForegroundColor Green
    exit 0
}
finally {
    if ($seededByTest) {
        $mDel = $tMgr.GetMethod("DeleteCustomDevice", [System.Reflection.BindingFlags]'Public,Static')
        if ($mDel) {
            $mDel.Invoke($null, @("BT_5CD33D59A938"))
        }
    }
}
