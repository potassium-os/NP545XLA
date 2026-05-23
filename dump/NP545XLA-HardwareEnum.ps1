# NP545XLA-HardwareEnum.ps1
# Run as Administrator on the Windows 11 ARM64 box
# Dumps everything we need to build a device tree for this SoC
#
# Usage: Set-ExecutionPolicy Bypass -Scope Process; .\NP545XLA-HardwareEnum.ps1
# Output: .\NP545XLA-hw-dump\

param(
    [string]$OutputDir = ".\NP545XLA-hw-dump"
)

$ErrorActionPreference = "Continue"

function Write-Section($title) {
    $sep = "=" * 72
    Add-Content -Path $script:logFile -Value "`n$sep`n# $title`n$sep"
    Write-Host "`n[*] $title" -ForegroundColor Cyan
}

function Run-Cmd($label, $cmd) {
    Add-Content -Path $script:logFile -Value "`n--- $label ---"
    try {
        $result = Invoke-Expression $cmd 2>&1
        $result | Out-String | Add-Content -Path $script:logFile
        Write-Host "  [OK] $label" -ForegroundColor Green
    } catch {
        "ERROR: $_" | Add-Content -Path $script:logFile
        Write-Host "  [FAIL] $label - $_" -ForegroundColor Red
    }
}

# --- Setup ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] Not running as Administrator. Some data will be missing. Re-run elevated." -ForegroundColor Yellow
    Write-Host "    Press Ctrl+C to abort, or Enter to continue anyway..."
    Read-Host
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$script:logFile = Join-Path $OutputDir "hw-enum.txt"
"" | Set-Content -Path $script:logFile

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"NP545XLA Hardware Enumeration - $timestamp" | Add-Content -Path $script:logFile
"PowerShell $($PSVersionTable.PSVersion)" | Add-Content -Path $script:logFile

Write-Host "[*] Dumping to $OutputDir" -ForegroundColor Cyan

# =============================================================================
# 1. ACPI TABLES
# =============================================================================
Write-Section "1. ACPI Tables"

# Check if acpidump is available
$acpiDumpPath = Get-Command "acpidump.exe" -ErrorAction SilentlyContinue
$iaslPath = Get-Command "iasl.exe" -ErrorAction SilentlyContinue

if ($acpiDumpPath) {
    Write-Host "  [OK] acpidump found at $($acpiDumpPath.Source)" -ForegroundColor Green
    Push-Location $OutputDir
    try {
        Run-Cmd "acpidump" "acpidump.exe -b"
        Write-Host "  [*] Disassembling ACPI tables..." -ForegroundColor Yellow
        Get-ChildItem -Filter "*.dat" | ForEach-Object {
            if ($iaslPath) {
                Run-Cmd "iasl -d $($_.Name)" "iasl.exe -d `"$($_.FullName)`""
            } else {
                Write-Host "  [!] iasl.exe not found - skipping disassembly of $($_.Name)" -ForegroundColor Yellow
                Write-Host "      Download from https://www.acpica.org/downloads" -ForegroundColor Yellow
            }
        }
    } finally {
        Pop-Location
    }
} else {
    Write-Host "  [!] acpidump.exe not found in PATH" -ForegroundColor Yellow
    Write-Host "      Download from https://www.acpica.org/downloads" -ForegroundColor Yellow
    Write-Host "      Place acpidump.exe and iasl.exe in PATH or next to this script, then re-run" -ForegroundColor Yellow

    # Fallback: try to extract ACPI tables from registry
    Write-Host "  [*] Attempting registry-based ACPI info..." -ForegroundColor Yellow
    Run-Cmd "ACPI namespace (registry)" "Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PSChildName"
    Run-Cmd "ACPI HAL" "Get-WmiObject -Namespace root\wmi -Class MSACPI_MemoryDevice -ErrorAction SilentlyContinue | Format-List"
}

# Always dump the raw ACPI table from EFI if we can
$efiAcpiDir = Join-Path $OutputDir "efi-acpi"
Run-Cmd "Mount EFI partition" 'mountvol S: /s 2>$null; if (Test-Path "S:\") { "EFI mounted at S:" } else { "EFI mount failed or already mounted" }'
if (Test-Path "S:\") {
    New-Item -ItemType Directory -Force -Path $efiAcpiDir | Out-Null
    # Some UEFI implementations expose ACPI tables here
    Run-Cmd "EFI root listing" "Get-ChildItem 'S:\' -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object FullName"
}

# =============================================================================
# 2. SYSTEM INFO
# =============================================================================
Write-Section "2. System Information"

Run-Cmd "ComputerInfo" "Get-ComputerInfo | Format-List"
Run-Cmd "OS version" "[System.Environment]::OSVersion | Format-List"
Run-Cmd "CPU" "Get-WmiObject Win32_Processor | Format-List Name, NumberOfCores, NumberOfLogicalProcessors, Architecture, Manufacturer, DeviceID, Status"
Run-Cmd "CPU (detailed)" "Get-CimInstance Win32_Processor | Select-Object * | Format-List"
Run-Cmd "Physical memory" "Get-WmiObject Win32_PhysicalMemory | Format-List BankLabel, Capacity, Speed, Manufacturer, DeviceLocator"
Run-Cmd "Memory summary" "Get-WmiObject Win32_PhysicalMemory | Measure-Object Capacity -Sum | Select-Object Count, @{Name='TotalGB';Expression={[math]::Round($_.Sum/1GB,2)}}"
Run-Cmd "BIOS/UEFI" "Get-WmiObject Win32_BIOS | Format-List *"
Run-Cmd "Board" "Get-WmiObject Win32_BaseBoard | Format-List *"
Run-Cmd "System enclosure" "Get-WmiObject Win32_SystemEnclosure | Format-List *"

# =============================================================================
# 3. PCI DEVICES
# =============================================================================
Write-Section "3. PCI Devices"

Run-Cmd "PnP devices (PCI)" 'Get-PnpDevice -Class "System","Processor","USB","Net","Display","MEDIA","Bluetooth","Keyboard","Mouse","HIDClass" -ErrorAction SilentlyContinue | Format-Table Status, Class, FriendlyName, InstanceId -AutoSize'
Run-Cmd "All PnP devices" 'Get-PnpDevice | Where-Object {$_.InstanceId -match "ACPI|PCI"} | Format-Table Status, Class, FriendlyName, InstanceId -AutoSize'
Run-Cmd "PnP device details (ACPI)" 'Get-PnpDevice | Where-Object {$_.InstanceId -match "^ACPI\\"} | ForEach-Object { Get-PnpDeviceProperty $_.InstanceId -KeyName "DEVPKEY_Device_HardwareIds","DEVPKEY_Device_CompatibleIds","DEVPKEY_Device_LocationInfo","DEVPKEY_Device_DriverVersion" -ErrorAction SilentlyContinue } | Format-List'

# Full device list with hardware IDs
$devFile = Join-Path $OutputDir "devices-with-hwid.txt"
"Full device enumeration with hardware IDs`n" | Set-Content -Path $devFile
Get-PnpDevice | Where-Object { $_.Status -ne "Error" } | ForEach-Object {
    $dev = $_
    $hwids = (Get-PnpDeviceProperty $dev.InstanceId -KeyName "DEVPKEY_Device_HardwareIds" -ErrorAction SilentlyContinue).Data
    $compids = (Get-PnpDeviceProperty $dev.InstanceId -KeyName "DEVPKEY_Device_CompatibleIds" -ErrorAction SilentlyContinue).Data
    $loc = (Get-PnpDeviceProperty $dev.InstanceId -KeyName "DEVPKEY_Device_LocationInfo" -ErrorAction SilentlyContinue).Data
    "Device: $($dev.FriendlyName)" | Add-Content -Path $devFile
    "  Class: $($dev.Class)" | Add-Content -Path $devFile
    "  Instance: $($dev.InstanceId)" | Add-Content -Path $devFile
    "  Location: $loc" | Add-Content -Path $devFile
    "  HWIDs: $($hwids -join ', ')" | Add-Content -Path $devFile
    "  CompatIDs: $($compids -join ', ')" | Add-Content -Path $devFile
    "" | Add-Content -Path $devFile
}
Write-Host "  [OK] Full device list written to devices-with-hwid.txt" -ForegroundColor Green

# =============================================================================
# 4. I2C DEVICES (keyboard, touchpad, touchscreen)
# =============================================================================
Write-Section "4. I2C Devices"

Run-Cmd "I2C controllers" 'Get-PnpDevice | Where-Object {$_.FriendlyName -match "I2C|I2CController"} | Format-List *'
Run-Cmd "I2C child devices" 'Get-PnpDevice | Where-Object {$_.InstanceId -match "I2C"} | Format-Table FriendlyName, InstanceId -AutoSize'
Run-Cmd "HID devices (I2C-attached)" 'Get-PnpDevice | Where-Object {$_.InstanceId -match "I2C" -and $_.Class -match "HID|Keyboard|Mouse"} | Format-List *'

# Try to get I2C device addresses from registry
Run-Cmd "I2C registry details" 'Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI" -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "I2C" } | ForEach-Object { $_.Name; $_.GetValueNames() | ForEach-Object { "  $_ = $(($_.PSBase | Get-ItemProperty -Name $_ -ErrorAction SilentlyContinue))" } } | Out-String'

# =============================================================================
# 5. DISPLAY / GPU
# =============================================================================
Write-Section "5. Display / GPU"

Run-Cmd "Display adapters" "Get-WmiObject Win32_VideoController | Format-List *"
Run-Cmd "Monitor" "Get-WmiObject Win32_DesktopMonitor | Format-List *"
Run-Cmd "PnP display devices" 'Get-PnpDevice -Class "Display","Monitor" -ErrorAction SilentlyContinue | Format-List *'
Run-Cmd "Framebuffer info" "Get-WmiObject Win32_VideoController | Select-Object Name, CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate, AdapterRAM, DriverVersion, VideoModeDescription"

# =============================================================================
# 6. NETWORK (WiFi / LTE / Bluetooth)
# =============================================================================
Write-Section "6. Network Devices"

Run-Cmd "Network adapters" "Get-WmiObject Win32_NetworkAdapter | Format-List Name, DeviceID, MACAddress, AdapterType, Speed, Manufacturer, NetConnectionID, PhysicalAdapter"
Run-Cmd "WiFi adapter detail" 'Get-NetAdapter | Where-Object {$_.InterfaceDescription -match "Wireless|Wi-Fi|802.11| Qualcomm|QCA"} | Format-List *'
Run-Cmd "Bluetooth" 'Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue | Format-List *'
Run-Cmd "Bluetooth radio" "Get-Service bthserv | Format-List *"

# =============================================================================
# 7. STORAGE (UFS / NVMe)
# =============================================================================
Write-Section "7. Storage Devices"

Run-Cmd "Disks" "Get-Disk | Format-List Number, FriendlyName, SerialNumber, Size, PartitionStyle, BusType, MediaKind, OperationalStatus"
Run-Cmd "Physical disks" "Get-PhysicalDisk | Format-List *"
Run-Cmd "Partitions" "Get-Partition | Format-List *"
Run-Cmd "Volumes" "Get-Volume | Format-List *"
Run-Cmd "Disk drives (WMI)" "Get-WmiObject Win32_DiskDrive | Format-List Name, Model, Size, InterfaceType, MediaType, SerialNumber, FirmwareRevision"

# =============================================================================
# 8. USB
# =============================================================================
Write-Section "8. USB Controllers and Devices"

Run-Cmd "USB controllers" 'Get-PnpDevice -Class USB -ErrorAction SilentlyContinue | Format-Table FriendlyName, InstanceId, Status -AutoSize'
Run-Cmd "USB devices" 'Get-WmiObject Win32_USBControllerDevice | ForEach-Object { $_.Dependent } | Format-List Name, DeviceID, Manufacturer'
Run-Cmd "USB controller detail" "Get-WmiObject Win32_USBController | Format-List *"

# =============================================================================
# 9. GPIO / INTERRUPTS / RESOURCES
# =============================================================================
Write-Section "9. Interrupts and Resource Assignments"

# This is the gold for DTS interrupt specifiers
Run-Cmd "Interrupt assignments (WMI)" 'Get-WmiObject Win32_IRQResource | Format-List *'
Run-Cmd "DMA channels" 'Get-WmiObject Win32_DMAChannel | Format-List *'
Run-Cmd "Memory-mapped I/O" 'Get-WmiObject Win32_DeviceMemoryAddress | Format-List *'
Run-Cmd "Port I/O" 'Get-WmiObject Win32_PortResource | Format-List *'

# =============================================================================
# 10. POWER / REGULATOR INFO
# =============================================================================
Write-Section "10. Power and Battery"

Run-Cmd "Battery" "Get-WmiObject Win32_Battery | Format-List *"
Run-Cmd "Portable battery" "Get-WmiObject Win32_PortableBattery | Format-List *"
Run-Cmd "Power plan" "powercfg /query"
Run-Cmd "Sleep states" "powercfg /availablesleepstates"

# =============================================================================
# 11. FIRMWARE / DRIVERS
# =============================================================================
Write-Section "11. Firmware and Driver Files"

# Pull driver file paths for Qualcomm devices
$fwFile = Join-Path $OutputDir "qualcomm-drivers.txt"
"Qualcomm driver file locations`n" | Set-Content -Path $fwFile
Get-WmiObject Win32_PnPSignedDriver | Where-Object { $_.DeviceName -match "Qualcomm|QCA|QCOM|Snapdragon|ath|Atheros" } | ForEach-Object {
    "Device: $($_.DeviceName)" | Add-Content -Path $fwFile
    "  Driver: $($_.DriverVersion)" | Add-Content -Path $fwFile
    "  Inf: $($_.InfName)" | Add-Content -Path $fwFile
    "  DriverDate: $($_.DriverDate)" | Add-Content -Path $fwFile
    "  DeviceID: $($_.DeviceID)" | Add-Content -Path $fwFile
    "" | Add-Content -Path $fwFile
}
Write-Host "  [OK] Qualcomm driver info written to qualcomm-drivers.txt" -ForegroundColor Green

# Copy firmware .mbn files if we can find them
$fwDumpDir = Join-Path $OutputDir "firmware-blobs"
Run-Cmd "Find .mbn firmware files" 'Get-ChildItem "C:\Windows\System32\drivers" -Filter "*.mbn" -Recurse -ErrorAction SilentlyContinue | Select-Object FullName, Length'
Run-Cmd "Find .elf firmware files" 'Get-ChildItem "C:\Windows\System32\drivers" -Filter "*.elf" -Recurse -ErrorAction SilentlyContinue | Select-Object FullName, Length'
Run-Cmd "Find Qualcomm .sys drivers" 'Get-ChildItem "C:\Windows\System32\drivers" -Filter "qcom*" -Recurse -ErrorAction SilentlyContinue | Select-Object FullName, Length'

# =============================================================================
# 12. DEVICE TREE CLUES FROM REGISTRY
# =============================================================================
Write-Section "12. ACPI Device Paths (for DTS compatible strings)"

# Map ACPI device paths to hardware IDs — this is how you find DTS compatible strings
$acpiFile = Join-Path $OutputDir "acpi-device-map.txt"
"ACPI Device Path -> Hardware ID mapping`n" | Set-Content -Path $acpiFile
Get-PnpDevice | Where-Object { $_.InstanceId -match "^ACPI\\" } | ForEach-Object {
    $dev = $_
    $hwids = (Get-PnpDeviceProperty $dev.InstanceId -KeyName "DEVPKEY_Device_HardwareIds" -ErrorAction SilentlyContinue).Data
    # Extract ACPI path: ACPI\VEN_QCOM&DEV_0818 -> QCOM0818
    $acpiPath = ""
    if ($dev.InstanceId -match "ACPI\\(.+?)\\") { $acpiPath = $Matches[1] }
    "$acpiPath -> $($dev.FriendlyName)" | Add-Content -Path $acpiFile
    "  HWIDs: $($hwids -join ', ')" | Add-Content -Path $acpiFile
    "  InstanceId: $($dev.InstanceId)" | Add-Content -Path $acpiFile
    "" | Add-Content -Path $acpiFile
}
Write-Host "  [OK] ACPI device map written to acpi-device-map.txt" -ForegroundColor Green

# =============================================================================
# 13. PLATFORM-SPECIFIC
# =============================================================================
Write-Section "13. Samsung Platform Specific"

Run-Cmd "Samsung software" 'Get-WmiObject Win32_Product | Where-Object { $_.Name -match "Samsung" } | Format-List Name, Version'
Run-Cmd "Samsung services" 'Get-Service | Where-Object { $_.DisplayName -match "Samsung" } | Format-List *'
Run-Cmd "Sensor devices" 'Get-PnpDevice -Class Sensor -ErrorAction SilentlyContinue | Format-List *'
Run-Cmd "Camera" 'Get-PnpDevice -Class Camera -ErrorAction SilentlyContinue | Format-List *'
Run-Cmd "Audio" 'Get-PnpDevice -Class MEDIA -ErrorAction SilentlyContinue | Format-List *'
Run-Cmd "Audio endpoints" 'Get-PnpDevice | Where-Object { $_.FriendlyName -match "audio|speaker|microphone|headphone" } | Format-List *'

# =============================================================================
# 14. DSDT/SSDT TEXT EXTRACTION (fallback without acpidump)
# =============================================================================
Write-Section "14. ACPI Namespace Walk (fallback)"

# Walk the ACPI namespace in the registry — not as good as iasl output but better than nothing
$nsFile = Join-Path $OutputDir "acpi-namespace.txt"
"ACPI namespace from registry`n" | Set-Content -Path $nsFile
try {
    $acpiEnum = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI" -ErrorAction SilentlyContinue
    foreach ($vendor in $acpiEnum) {
        $vendorName = $vendor.PSChildName
        foreach ($device in Get-ChildItem $vendor.PSPath -ErrorAction SilentlyContinue) {
            $deviceName = $device.PSChildName
            foreach ($instance in Get-ChildItem $device.PSPath -ErrorAction SilentlyContinue) {
                $instName = $instance.PSChildName
                $props = Get-ItemProperty $instance.PSPath -ErrorAction SilentlyContinue
                "ACPI\$vendorName\$deviceName\$instName" | Add-Content -Path $nsFile
                if ($props.FriendlyName) { "  FriendlyName: $($props.FriendlyName)" | Add-Content -Path $nsFile }
                if ($props.Class) { "  Class: $($props.Class)" | Add-Content -Path $nsFile }
                if ($props.Driver) { "  Driver: $($props.Driver)" | Add-Content -Path $nsFile }
                "" | Add-Content -Path $nsFile
            }
        }
    }
    Write-Host "  [OK] ACPI namespace written to acpi-namespace.txt" -ForegroundColor Green
} catch {
    "Failed to walk ACPI namespace: $_" | Add-Content -Path $nsFile
    Write-Host "  [FAIL] ACPI namespace walk failed" -ForegroundColor Red
}

# =============================================================================
# 15. FLATTENED DEVICETREE (if exposed by firmware)
# =============================================================================
Write-Section "15. FDT/DTB from EFI (if available)"

# Some ARM Windows machines expose a DTB in EFI
Run-Cmd "EFI firmware vars" 'Get-ChildItem "S:\EFI\" -Recurse -ErrorAction SilentlyContinue | Select-Object FullName, Length'
Run-Cmd "Look for .dtb files" 'Get-ChildItem "S:\" -Filter "*.dtb" -Recurse -ErrorAction SilentlyContinue | Select-Object FullName'
Run-Cmd "Look for .dtbo files" 'Get-ChildItem "S:\" -Filter "*.dtbo" -Recurse -ErrorAction SilentlyContinue | Select-Object FullName'
Run-Cmd "Look for config.txt / cmdline" 'Get-ChildItem "S:\" -Include "config.txt","cmdline.txt","bcm*.dtb" -Recurse -ErrorAction SilentlyContinue | Select-Object FullName'

# =============================================================================
# DONE
# =============================================================================
Write-Section "Done!"

$summary = @"
Enumeration complete. Output in: $OutputDir

Key files to check:
  - hw-enum.txt          : Full text dump of everything
  - devices-with-hwid.txt: All devices with hardware IDs
  - acpi-device-map.txt  : ACPI path -> hardware ID mapping
  - acpi-namespace.txt   : ACPI namespace from registry
  - qualcomm-drivers.txt : Qualcomm driver file paths
  - DSDT.dsl / SSDT*.dsl: Disassembled ACPI tables (if acpidump+iasl were available)

NEXT STEPS:
  1. If acpidump/iasl weren't available, download from https://www.acpica.org/downloads
     and re-run this script. The ACPI tables are the most critical data.
  2. Copy the entire NP545XLA-hw-dump folder off the machine.
  3. Feed DSDT.dsl into your DTS construction process.
"@

$summary | Add-Content -Path $script:logFile
Write-Host $summary -ForegroundColor Yellow
