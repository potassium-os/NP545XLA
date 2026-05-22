# NP545XLA-ReDisasm.ps1
# Re-disassemble ACPI tables with iasl -e to decode raw _CRS resource buffers
# The MSFT compiler emits raw hex buffers; iasl -e can resolve them into
# readable I2CSerialBus, GpioInt, etc. macros when it has full table context.
#
# Prerequisites: acpidump.exe and iasl.exe in PATH or next to this script
# Download from: https://www.acpica.org/downloads
#
# Usage: Set-ExecutionPolicy Bypass -Scope Process; .\NP545XLA-ReDisasm.ps1
# Run in the NP545XLA-hw-dump directory (where the .dat files already are)

param(
    [string]$DumpDir = ".\NP545XLA-hw-dump"
)

$ErrorActionPreference = "Continue"

if (-not (Test-Path $DumpDir)) {
    Write-Host "[!] Dump directory not found: $DumpDir" -ForegroundColor Red
    Write-Host "    Run NP545XLA-HardwareEnum.ps1 first, or specify the path with -DumpDir" -ForegroundColor Red
    exit 1
}

$iaslPath = Get-Command "iasl.exe" -ErrorAction SilentlyContinue
if (-not $iaslPath) {
    # Check next to the script
    $localIasl = Join-Path $PSScriptRoot "iasl.exe"
    if (Test-Path $localIasl) {
        $iaslPath = [System.Management.Automation.CommandInfo]$localIasl
    }
}

if (-not $iaslPath) {
    Write-Host "[!] iasl.exe not found. Download from https://www.acpica.org/downloads" -ForegroundColor Red
    Write-Host "    Place it in PATH or next to this script." -ForegroundColor Red
    exit 1
}

Write-Host "[*] Using iasl: $($iaslPath.Source)" -ForegroundColor Cyan

# Collect all .dat files for -e inclusion
$datFiles = Get-ChildItem -Path $DumpDir -Filter "*.dat" | Sort-Object Name
if ($datFiles.Count -eq 0) {
    Write-Host "[!] No .dat files found in $DumpDir" -ForegroundColor Red
    exit 1
}

Write-Host "[*] Found $($datFiles.Count) .dat files:" -ForegroundColor Cyan
$datFiles | ForEach-Object { Write-Host "    $($_.Name) ($([math]::Round($_.Length/1024, 1)) KB)" }

# =============================================================================
# Step 1: Re-disassemble DSDT with all SSDTs loaded via -e
# =============================================================================
Write-Host "`n[*] Step 1: Re-disassembling DSDT with full table context..." -ForegroundColor Cyan

# Build the -e argument with all table files except the DSDT itself
$externalTables = $datFiles | Where-Object { $_.Name -ne "dsdt.dat" } | ForEach-Object { $_.FullName }
$eArg = ($externalTables -join ",")

$outputDir = Join-Path $DumpDir "redisasm"
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

# Copy dat files to output dir for iasl to work on
$datFiles | Copy-Item -Destination $outputDir

Push-Location $outputDir
try {
    # iasl -e: include external tables
    # -fe: external reference file 
    # -l: create listing file with offsets
    # -vi: verbose include
    $dsdtDat = "dsdt.dat"
    
    Write-Host "    Running: iasl -e `"$eArg`" -d $dsdtDat" -ForegroundColor Yellow
    $result = & iasl.exe -e $eArg -d $dsdtDat 2>&1
    $result | Write-Host
    
    if (Test-Path "dsdt.dsl") {
        $size = (Get-Item "dsdt.dsl").Length
        Write-Host "    [OK] dsdt.dsl created ($([math]::Round($size/1024)) KB)" -ForegroundColor Green
    } else {
        Write-Host "    [FAIL] dsdt.dsl not created" -ForegroundColor Red
    }
} finally {
    Pop-Location
}

# =============================================================================
# Step 2: Re-disassemble each SSDT individually with DSDT context
# =============================================================================
Write-Host "`n[*] Step 2: Re-disassembling individual SSDTs..." -ForegroundColor Cyan

$ssdtFiles = $datFiles | Where-Object { $_.Name -ne "dsdt.dat" -and $_.Name -ne "xsdt.dat" }
foreach ($ssdt in $ssdtFiles) {
    Push-Location $outputDir
    try {
        Write-Host "    Processing: $($ssdt.Name)" -ForegroundColor Yellow
        $otherTables = $datFiles | Where-Object { $_.Name -ne $ssdt.Name } | ForEach-Object { Join-Path $outputDir $_.Name }
        $eArg2 = ($otherTables -join ",")
        & iasl.exe -e $eArg2 -d $ssdt.Name 2>&1 | Out-Null
        
        $dslName = $ssdt.BaseName + ".dsl"
        if (Test-Path $dslName) {
            Write-Host "    [OK] $dslName" -ForegroundColor Green
        } else {
            Write-Host "    [SKIP] $dslName not created" -ForegroundColor Yellow
        }
    } finally {
        Pop-Location
    }
}

# =============================================================================
# Step 3: Extract and decode all _CRS resource buffers from DSDT
# =============================================================================
Write-Host "`n[*] Step 3: Checking if _CRS buffers were decoded..." -ForegroundColor Cyan

$redisasmDsdt = Join-Path $outputDir "dsdt.dsl"
if (Test-Path $redisasmDsdt) {
    # Count human-readable resource macros vs raw buffers in _CRS methods
    $i2cSerial = Select-String -Path $redisasmDsdt -Pattern "I2CSerialBus" -SimpleMatch
    $gpioInt = Select-String -Path $redisasmDsdt -Pattern "GpioInt" -SimpleMatch
    $rawBuf = Select-String -Path $redisasmDsdt -Pattern "Name \(RBUF, Buffer" 
    
    Write-Host "    I2CSerialBus macros found: $($i2cSerial.Count)" -ForegroundColor $(if ($i2cSerial.Count -gt 0) {"Green"} else {"Yellow"})
    Write-Host "    GpioInt macros found:       $($gpioInt.Count)" -ForegroundColor $(if ($gpioInt.Count -gt 0) {"Green"} else {"Yellow"})
    Write-Host "    Raw RBUF buffers remaining:  $($rawBuf.Count)" -ForegroundColor $(if ($rawBuf.Count -gt 0) {"Yellow"} else {"Green"})
    
    if ($i2cSerial.Count -gt 0) {
        Write-Host "`n    [*] iasl -e successfully decoded resource templates!" -ForegroundColor Green
        Write-Host "    I2C device addresses are now readable." -ForegroundColor Green
    } else {
        Write-Host "`n    [!] iasl -e did NOT decode the raw buffers." -ForegroundColor Yellow
        Write-Host "    This is common with MSFT-compiled ACPI. Falling back to manual decode..." -ForegroundColor Yellow
    }
}

# =============================================================================
# Step 4: Fallback — manual ACPI resource descriptor decoder
# =============================================================================
Write-Host "`n[*] Step 4: Running manual CRS buffer decoder..." -ForegroundColor Cyan

$decodedFile = Join-Path $DumpDir "crs-decoded.txt"
"# Decoded ACPI _CRS Resource Buffers`n# Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n" | Set-Content -Path $decodedFile

# Parse the ORIGINAL dsdt.dsl for raw RBUF buffers and decode them
$originalDsdt = Join-Path $DumpDir "dsdt.dsl"
$content = Get-Content $originalDsdt -Raw

# Regex to find _CRS methods with RBUF buffers
# We look for patterns like:
#   Device (I2C1) { ... Name (_HID, "QCOM0411") ... Name (RBUF, Buffer (0x17) { ... } }
# But that's complex. Instead, find each RBUF buffer, extract context, decode bytes.

$lines = Get-Content $originalDsdt

$i = 0
$deviceStack = [System.Collections.Stack]::new()
$decodedCount = 0

while ($i -lt $lines.Count) {
    $line = $lines[$i]
    
    # Track Device scope
    if ($line -match '^\s*(Device|Scope)\s*\(\s*(\S+)\s*\)') {
        $deviceStack.Push $Matches[2]
    }
    
    # Find _HID for context
    $currentHid = ""
    if ($line -match '_HID.*"([^"]+)"') {
        $currentHid = $Matches[1]
    }
    if ($line -match '_HID.*EisaId\s*\("([^"]+)"') {
        $currentHid = $Matches[1]
    }
    
    # Find RBUF buffer
    if ($line -match 'Name\s*\(RBUF,\s*Buffer\s*\((0x[0-9A-Fa-f]+)\)') {
        $bufSize = [Convert]::ToInt32($Matches[1], 16)
        $byteList = [System.Collections.ArrayList]::new()
        $i++
        
        # Collect all the hex bytes from the buffer
        while ($i -lt $lines.Count) {
            $bufLine = $lines[$i]
            if ($bufLine -match '/\*\s*([0-9A-Fa-f]{4})\s*\*/\s*(.+)') {
                $hexPart = $Matches[2]
                # Extract all 0xNN values
                $hexBytes = [regex]::Matches($hexPart, '0x([0-9A-Fa-f]{2})')
                foreach ($hb in $hexBytes) {
                    [void]$byteList.Add([Convert]::ToByte($hb.Groups[1].Value, 16))
                }
            }
            if ($bufLine -match '\}\)') {
                break
            }
            $i++
        }
        
        $bytes = $byteList.ToArray()
        $devicePath = ($deviceStack.ToArray() -join ".")
        
        # Decode the resource descriptors
        $decoded = Decode-ResourceBuffer -Bytes $bytes -DevicePath $devicePath -Hid $currentHid
        if ($decoded) {
            $decoded | Add-Content -Path $decodedFile
            $decodedCount++
        }
    }
    
    $i++
}

Write-Host "    [OK] Decoded $decodedCount resource buffers -> crs-decoded.txt" -ForegroundColor Green

# =============================================================================
# Helper: Decode ACPI Small/Large resource descriptors
# =============================================================================
function Decode-ResourceBuffer {
    param([byte[]]$Bytes, [string]$DevicePath, [string]$Hid)
    
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("`n=== $DevicePath (_HID: $Hid) ===")
    
    $pos = 0
    while ($pos -lt $Bytes.Count) {
        $b = $Bytes[$pos]
        
        # Check if large descriptor (bit 7 set)
        if ($b -band 0x80) {
            # Large descriptor
            $type = $b -band 0x7F
            $len = ($Bytes[$pos+1]) + ($Bytes[$pos+2] -shl 8)
            
            switch ($type) {
                0x06 { # I2C Serial Bus (0x8E)
                    if ($pos + 6 -le $Bytes.Count) {
                        $slaveAddr = ($Bytes[$pos+5] -shl 8) + $Bytes[$pos+4]
                        $slaveAddr7 = $slaveAddr -shr 1
                        $mode = $Bytes[$pos+3]  # 0x00=Initiator
                        $speed = switch ($Bytes[$pos+6]) {
                            0x01 { "100KHz" }
                            0x02 { "400KHz" }
                            0x03 { "1MHz" }
                            0x04 { "3.4MHz" }
                            default { "0x$([Convert]::ToString($Bytes[$pos+6], 16))" }
                        }
                        # Resource source string starts at pos+7
                        $srcStart = $pos + 7
                        $src = ""
                        for ($s = $srcStart; $s -lt $Bytes.Count -and $Bytes[$s] -ne 0; $s++) {
                            $src += [char]$Bytes[$s]
                        }
                        [void]$sb.AppendLine("  I2CSerialBus: addr=0x$($slaveAddr7.ToString('X2')) ($slaveAddr7), speed=$speed, controller=$src")
                    }
                }
                0x08 { # GPIO Connection (0x8C)
                    if ($pos + 20 -le $Bytes.Count) {
                        $gpioType = $Bytes[$pos+3]  # 0x00=Interrupt, 0x01=I/O
                        $pinConfig = $Bytes[$pos+8]  # 0x00=default, 0x01=pull-up, 0x02=pull-down, 0x03=no-pull
                        $debounce = [BitConverter]::ToUInt16($Bytes, $pos+10)
                        $pinTableOffset = [BitConverter]::ToUInt16($Bytes, $pos+14)
                        $numPins = ([BitConverter]::ToUInt16($Bytes, $pos+16)) / 2
                        
                        # Pin numbers are at pinTableOffset from descriptor start
                        $pinBase = $pos + $pinTableOffset
                        $pins = @()
                        for ($p = 0; $p -lt $numPins -and ($pinBase + $p*2 + 1) -lt $Bytes.Count; $p++) {
                            $pinNum = [BitConverter]::ToUInt16($Bytes, $pinBase + $p*2)
                            $pins += $pinNum
                        }
                        
                        # Resource source (GPIO controller) string
                        $srcOffset = $pinBase + $numPins * 2
                        $src = ""
                        for ($s = $srcOffset; $s -lt $Bytes.Count -and $Bytes[$s] -ne 0; $s++) {
                            $src += [char]$Bytes[$s]
                        }
                        
                        $typeStr = if ($gpioType -eq 0x00) { "GpioInt" } else { "GpioIO" }
                        $pullStr = switch ($pinConfig) {
                            0x00 { "default" }
                            0x01 { "pull-up" }
                            0x02 { "pull-down" }
                            0x03 { "no-pull" }
                            default { "0x$([Convert]::ToString($pinConfig, 16))" }
                        }
                        [void]$sb.AppendLine("  $typeStr: pins=$($pins -join ','), $pullStr, debounce=${debounce}us, controller=$src")
                    }
                }
                0x09 { # Interrupt (0x89) — extended format
                    if ($pos + 6 -le $Bytes.Count) {
                        $flags = $Bytes[$pos+3]
                        $irqCount = ($Bytes[$pos+4] -shl 8) + $Bytes[$pos+5]
                        # IRQ numbers are bitmask — decode
                        $irqs = @()
                        for ($w = 0; $w -lt $irqCount; $w++) {
                            if ($pos + 6 + $w*4 + 3 -lt $Bytes.Count) {
                                $mask = [BitConverter]::ToUInt32($Bytes, $pos + 6 + $w*4)
                                for ($bit = 0; $bit -lt 32; $bit++) {
                                    if ($mask -band (1 -shl $bit)) { $irqs += $bit + ($w * 32) }
                                }
                            }
                        }
                        $trigger = if ($flags -band 0x01) { "level" } else { "edge" }
                        $polarity = if ($flags -band 0x02) { "active-low" } else { "active-high" }
                        $sharing = if ($flags -band 0x04) { "shared" } else { "exclusive" }
                        [void]$sb.AppendLine("  Interrupt: irqs=$($irqs -join ','), $trigger, $polarity, $sharing")
                    }
                }
                0x01 { # Memory32Fixed (0x86)
                    if ($pos + 12 -le $Bytes.Count) {
                        $isWrite = $Bytes[$pos+3] -band 0x01
                        $base = [BitConverter]::ToUInt32($Bytes, $pos+4)
                        $length = [BitConverter]::ToUInt32($Bytes, $pos+8)
                        $rw = if ($isWrite) { "RW" } else { "RO" }
                        [void]$sb.AppendLine("  Memory32Fixed: base=0x$($base.ToString('X8')), len=0x$($length.ToString('X8')), $rw")
                    }
                }
                default {
                    [void]$sb.AppendLine("  LargeDesc type=0x$($type.ToString('X2')) len=$len (unknown)")
                }
            }
            $pos += 3 + $len
        } else {
            # Small descriptor
            $type = ($b -shr 3) -band 0x0F
            $len = $b -band 0x07
            
            switch ($type) {
                0x0F { # End tag
                    [void]$sb.AppendLine("  EndTag")
                    break
                }
                0x04 { # IRQ format
                    if ($len -gt 0) {
                        $mask = 0
                        for ($w = 0; $w -lt $len; $w++) {
                            $mask = $mask -bor ($Bytes[$pos+1+$w] -shl ($w*8))
                        }
                        $irqs = @()
                        for ($bit = 0; $bit -lt ($len*8); $bit++) {
                            if ($mask -band (1 -shl $bit)) { $irqs += $bit }
                        }
                        [void]$sb.AppendLine("  IRQ: $($irqs -join ',')")
                    }
                    break
                }
                0x08 { # IO Port
                    if ($len -ge 7) {
                        $decode = $Bytes[$pos+1]
                        $minAddr = ($Bytes[$pos+3] -shl 8) + $Bytes[$pos+2]
                        $maxAddr = ($Bytes[$pos+5] -shl 8) + $Bytes[$pos+4]
                        [void]$sb.AppendLine("  IOPort: 0x$($minAddr.ToString('X4'))-0x$($maxAddr.ToString('X4'))")
                    }
                    break
                }
                default {
                    if ($type -ne 0x00) {
                        [void]$sb.AppendLine("  SmallDesc type=0x$($type.ToString('X')) len=$len")
                    }
                }
            }
            $pos += 1 + $len
        }
    }
    
    return $sb.ToString()
}

# =============================================================================
# Summary
# =============================================================================
Write-Host "`n[*] Done! Files in $outputDir" -ForegroundColor Cyan
Write-Host "    - redisasm/dsdt.dsl  (re-disassembled with -e flag)" -ForegroundColor White
Write-Host "    - crs-decoded.txt    (manually decoded _CRS buffers)" -ForegroundColor White
Write-Host ""
Write-Host "Check redisasm/dsdt.dsl first — if iasl -e decoded the resources," -ForegroundColor Yellow
Write-Host "you'll see I2CSerialBus(), GpioInt() etc. instead of raw hex." -ForegroundColor Yellow
Write-Host "crs-decoded.txt is the fallback manual decode of the raw buffers." -ForegroundColor Yellow
