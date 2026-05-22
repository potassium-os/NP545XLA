# NP545XLA-ReDisasm.ps1
# Re-disassemble ACPI tables with iasl -e to decode raw _CRS resource buffers
# Also runs a manual CRS buffer decoder as fallback
#
# Prerequisites: iasl.exe in PATH (from https://www.acpica.org/downloads)
# Run in the same directory as NP545XLA-hw-dump/
#
# Usage: Set-ExecutionPolicy Bypass -Scope Process; .\NP545XLA-ReDisasm.ps1

param(
    [string]$DumpDir = ".\NP545XLA-hw-dump"
)

$ErrorActionPreference = "Continue"

# === DECODER FUNCTION (must be defined before use) ===
function Decode-ResourceBuffer {
    param([byte[]]$Bytes, [string]$DevicePath, [string]$Hid)

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("`n=== $DevicePath (_HID: $Hid) ===")

    $pos = 0
    while ($pos -lt $Bytes.Count) {
        $b = $Bytes[$pos]

        if ($b -band 0x80) {
            # Large descriptor
            $type = $b -band 0x7F
            $len = $Bytes[$pos+1] + ($Bytes[$pos+2] -shl 8)

            switch ($type) {
                0x06 { # I2C SerialBus
                    if ($pos + 6 -le $Bytes.Count) {
                        $slaveAddr = ($Bytes[$pos+5] -shl 8) + $Bytes[$pos+4]
                        $slaveAddr7 = $slaveAddr -shr 1
                        $speed = switch ($Bytes[$pos+6]) {
                            0x01 { "100KHz" }
                            0x02 { "400KHz" }
                            0x03 { "1MHz" }
                            0x04 { "3.4MHz" }
                            default { "0x$([Convert]::ToString($Bytes[$pos+6], 16))" }
                        }
                        $srcStart = $pos + 7
                        $src = ""
                        for ($s = $srcStart; $s -lt $Bytes.Count -and $Bytes[$s] -ne 0; $s++) {
                            $src += [char]$Bytes[$s]
                        }
                        $addrHex = $slaveAddr7.ToString('X2')
                        [void]$sb.AppendLine("  I2CSerialBus: addr=0x$addrHex ($slaveAddr7), speed=$speed, controller=$src")
                    }
                }
                0x08 { # GPIO Connection
                    if ($pos + 20 -le $Bytes.Count) {
                        $gpioType = $Bytes[$pos+3]
                        $pinConfig = $Bytes[$pos+8]
                        $debounce = [BitConverter]::ToUInt16($Bytes, $pos+10)
                        $pinTableOffset = [BitConverter]::ToUInt16($Bytes, $pos+14)
                        $numPins = [BitConverter]::ToUInt16($Bytes, $pos+16) / 2

                        $pinBase = $pos + $pinTableOffset
                        $pins = @()
                        for ($p = 0; $p -lt $numPins -and ($pinBase + $p*2 + 1) -lt $Bytes.Count; $p++) {
                            $pinNum = [BitConverter]::ToUInt16($Bytes, $pinBase + $p*2)
                            $pins += $pinNum
                        }

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
                        $pinList = $pins -join ','
                        [void]$sb.AppendLine("  ${typeStr}: pins=${pinList}, ${pullStr}, debounce=${debounce}us, controller=${src}")
                    }
                }
                0x09 { # Extended Interrupt
                    if ($pos + 6 -le $Bytes.Count) {
                        $flags = $Bytes[$pos+3]
                        $irqCount = ($Bytes[$pos+4] -shl 8) + $Bytes[$pos+5]
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
                        $irqList = $irqs -join ','
                        [void]$sb.AppendLine("  Interrupt: irqs=${irqList}, ${trigger}, ${polarity}, ${sharing}")
                    }
                }
                0x01 { # Memory32Fixed
                    if ($pos + 12 -le $Bytes.Count) {
                        $isWrite = $Bytes[$pos+3] -band 0x01
                        $base = [BitConverter]::ToUInt32($Bytes, $pos+4)
                        $length = [BitConverter]::ToUInt32($Bytes, $pos+8)
                        $rw = if ($isWrite) { "RW" } else { "RO" }
                        $baseHex = $base.ToString('X8')
                        $lenHex = $length.ToString('X8')
                        [void]$sb.AppendLine("  Memory32Fixed: base=0x${baseHex}, len=0x${lenHex}, $rw")
                    }
                }
                0x07 { # I2C SerialBus Type (rev2 format)
                    [void]$sb.AppendLine("  I2CSerialBusV2: (type=0x07, len=$len)")
                }
                0x0A { # Pin Function
                    [void]$sb.AppendLine("  PinFunction: (type=0x0A, len=$len)")
                }
                default {
                    $typeHex = $type.ToString('X2')
                    [void]$sb.AppendLine("  LargeDesc type=0x${typeHex} len=$len (unknown)")
                }
            }
            $pos += 3 + $len
        } else {
            # Small descriptor
            $type = ($b -shr 3) -band 0x0F
            $len = $b -band 0x07

            switch ($type) {
                0x0F { [void]$sb.AppendLine("  EndTag"); break }
                0x04 {
                    if ($len -gt 0) {
                        $mask = 0
                        for ($w = 0; $w -lt $len; $w++) {
                            $mask = $mask -bor ($Bytes[$pos+1+$w] -shl ($w*8))
                        }
                        $irqs = @()
                        for ($bit = 0; $bit -lt ($len*8); $bit++) {
                            if ($mask -band (1 -shl $bit)) { $irqs += $bit }
                        }
                        $irqList = $irqs -join ','
                        [void]$sb.AppendLine("  IRQ: ${irqList}")
                    }
                    break
                }
                0x08 {
                    if ($len -ge 7) {
                        $minAddr = ($Bytes[$pos+3] -shl 8) + $Bytes[$pos+2]
                        $maxAddr = ($Bytes[$pos+5] -shl 8) + $Bytes[$pos+4]
                        $minHex = $minAddr.ToString('X4')
                        $maxHex = $maxAddr.ToString('X4')
                        [void]$sb.AppendLine("  IOPort: 0x${minHex}-0x${maxHex}")
                    }
                    break
                }
                default {
                    if ($type -ne 0x00) {
                        $typeHex = $type.ToString('X')
                        [void]$sb.AppendLine("  SmallDesc type=0x${typeHex} len=$len")
                    }
                }
            }
            $pos += 1 + $len
        }
    }

    return $sb.ToString()
}

# === MAIN SCRIPT ===

if (-not (Test-Path $DumpDir)) {
    Write-Host "[!] Dump directory not found: $DumpDir" -ForegroundColor Red
    exit 1
}

$iaslExe = Get-Command "iasl.exe" -ErrorAction SilentlyContinue
if (-not $iaslExe) {
    Write-Host "[!] iasl.exe not found in PATH. Download from https://www.acpica.org/downloads" -ForegroundColor Red
    exit 1
}

Write-Host "[*] Using iasl: $($iaslExe.Source)" -ForegroundColor Cyan

$datFiles = Get-ChildItem -Path $DumpDir -Filter "*.dat" | Sort-Object Name
if ($datFiles.Count -eq 0) {
    Write-Host "[!] No .dat files found in $DumpDir" -ForegroundColor Red
    exit 1
}

Write-Host "[*] Found $($datFiles.Count) .dat files" -ForegroundColor Cyan

# Step 1: Re-disassemble DSDT with iasl -e (one -e per file)
Write-Host "`n[*] Step 1: Re-disassembling DSDT with full table context..." -ForegroundColor Cyan

$outputDir = Join-Path $DumpDir "redisasm"
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

# Copy all .dat files to the output dir so iasl can find them
$datFiles | Copy-Item -Destination $outputDir -Force

Push-Location $outputDir
try {
    # Build argument list: iasl -e file1 -e file2 -e file3 ... -d dsdt.dat
    $iaslArgs = @()
    $otherDats = Get-ChildItem -Path "." -Filter "*.dat" | Where-Object { $_.Name -ne "dsdt.dat" }
    foreach ($d in $otherDats) {
        $iaslArgs += "-e"
        $iaslArgs += $d.Name
    }
    $iaslArgs += "-d"
    $iaslArgs += "dsdt.dat"

    Write-Host "    Running: iasl $($iaslArgs -join ' ')" -ForegroundColor Yellow
    & iasl.exe @iaslArgs 2>&1 | ForEach-Object { Write-Host "    $_" }

    if (Test-Path "dsdt.dsl") {
        $size = (Get-Item "dsdt.dsl").Length
        Write-Host "    [OK] dsdt.dsl created ($([math]::Round($size/1024)) KB)" -ForegroundColor Green
    } else {
        Write-Host "    [FAIL] dsdt.dsl not created" -ForegroundColor Red
    }
} finally {
    Pop-Location
}

# Step 2: Check if _CRS buffers were decoded
Write-Host "`n[*] Step 2: Checking if _CRS buffers were decoded..." -ForegroundColor Cyan

$redisasmDsdt = Join-Path $outputDir "dsdt.dsl"
if (Test-Path $redisasmDsdt) {
    $i2cSerial = Select-String -Path $redisasmDsdt -Pattern "I2CSerialBus" -SimpleMatch
    $gpioInt = Select-String -Path $redisasmDsdt -Pattern "GpioInt" -SimpleMatch

    Write-Host "    I2CSerialBus macros found: $($i2cSerial.Count)" -ForegroundColor $(if ($i2cSerial.Count -gt 0) {"Green"} else {"Yellow"})
    Write-Host "    GpioInt macros found:       $($gpioInt.Count)" -ForegroundColor $(if ($gpioInt.Count -gt 0) {"Green"} else {"Yellow"})

    if ($i2cSerial.Count -gt 0) {
        Write-Host "    iasl -e decoded resource templates!" -ForegroundColor Green
    } else {
        Write-Host "    iasl -e did NOT decode the raw buffers. Running manual decoder..." -ForegroundColor Yellow
    }
} else {
    Write-Host "    No dsdt.dsl to check. Running manual decoder..." -ForegroundColor Yellow
}

# Step 3: Manual CRS buffer decoder (fallback / always run for completeness)
Write-Host "`n[*] Step 3: Running manual CRS buffer decoder on original dsdt.dsl..." -ForegroundColor Cyan

$originalDsdt = Join-Path $DumpDir "dsdt.dsl"
if (-not (Test-Path $originalDsdt)) {
    Write-Host "    [!] No original dsdt.dsl found at $originalDsdt" -ForegroundColor Red
    Write-Host "    Skipping manual decoder." -ForegroundColor Yellow
} else {
    $decodedFile = Join-Path $DumpDir "crs-decoded.txt"
    "# Decoded ACPI _CRS Resource Buffers`n# Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n" | Set-Content -Path $decodedFile

    $lines = Get-Content $originalDsdt
    $deviceStack = [System.Collections.Stack]::new()
    $lastHid = ""
    $decodedCount = 0

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        # Track Device scope
        if ($line -match '^\s*(Device|Scope)\s*\(\s*(\S+)\s*\)') {
            $deviceStack.Push($Matches[2])
        }

        # Track _HID
        if ($line -match '_HID.*"([^"]+)"') {
            $lastHid = $Matches[1]
        }

        # Find RBUF buffer
        if ($line -match 'Name\s*\(RBUF,\s*Buffer\s*\((0x[0-9A-Fa-f]+)\)') {
            $byteList = [System.Collections.ArrayList]::new()
            $i++

            while ($i -lt $lines.Count) {
                $bufLine = $lines[$i]
                if ($bufLine -match '/\*\s*([0-9A-Fa-f]{4})\s*\*/\s*(.+)') {
                    $hexPart = $Matches[2]
                    $hexBytes = [regex]::Matches($hexPart, '0x([0-9A-Fa-f]{2})')
                    foreach ($hb in $hexBytes) {
                        [void]$byteList.Add([Convert]::ToByte($hb.Groups[1].Value, 16))
                    }
                }
                if ($bufLine -match '\}\)') { break }
                $i++
            }

            $bytes = $byteList.ToArray()
            $devicePath = ($deviceStack.ToArray() -join ".")

            $decoded = Decode-ResourceBuffer -Bytes $bytes -DevicePath $devicePath -Hid $lastHid
            if ($decoded) {
                Add-Content -Path $decodedFile -Value $decoded
                $decodedCount++
            }
        }
    }

    Write-Host "    [OK] Decoded $decodedCount resource buffers -> crs-decoded.txt" -ForegroundColor Green
}

# Summary
Write-Host "`n[*] Done!" -ForegroundColor Cyan
Write-Host "    redisasm/dsdt.dsl  - iasl -e output (may have decoded macros)" -ForegroundColor White
Write-Host "    crs-decoded.txt    - manual CRS buffer decode" -ForegroundColor White
