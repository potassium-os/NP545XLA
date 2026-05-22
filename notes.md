# Samsung Galaxy Book Go 5G (NP545XLA) — Linux on SC8180XP

## The Situation

- **SoC:** Qualcomm Snapdragon 8cx Gen 2 (SC8180XP)
- **Current state:** Boots to /init handoff, then dies
- **Target:** Ubuntu 26.04 LTS (kernel 6.14 base)

SC8180XP is the **only** 8cx generation without mainline kernel support:
- SC8180X (Gen 1) — supported since 6.5
- SC8180XP (Gen 2) — **not supported**
- SC8280XP (Gen 3) — supported since 6.0
- X1E80100 (Gen 4) — supported since 6.8

The 'P' variant difference from SC8180X: "no integrated modem" (Konrad Dybcio, linux-arm-msm mailing list, 2025-06-25). Everything else is board/variant design differences.

SC8180XP was explicitly excluded from the Qualcomm/Lenovo/Arm/Linaro aarch64-laptops collaboration that brought up the other 8cx generations.

---

## Known Boot Quirks (from linux-surface Pro X — same SoC)

Source: https://github.com/linux-surface/surface-pro-x/wiki/Basic-Setup

### Kernel command line parameters

| Parameter | Required? | Why |
|-----------|-----------|-----|
| `efi=novamap` | **YES** — both ACPI and DT | Prevents lockups during early boot |
| `clk_ignore_unused` | YES — DT boot only | Prevents disabling "unused" clocks at late init, which causes lockups |

### NVMe in ACPI mode

Broken by mainline commit `8fd4391ee717` ("arm64: PCI: Exclude ACPI consumer resources from host bridge windows"). Needs reverting for ACPI NVMe access. DT mode should work without this revert if the DT describes the PCIe controller correctly.

**Implication:** ACPI boot is a dead end. DT is the path forward.

### Black screen on GPU handoff

Known issue when kernel switches from simplefb to GPU-based framebuffer. Wait 20 seconds or force-reboot. This is a display bring-up sequencing issue.

### Initramfs module requirements

If booting from USB, these modules must be in the initramfs (not all distros include them by default on ARM64):

- `phy-qcom-qmp`
- `phy-qcom-snps-femto-v2`
- `dwc3-qcom`
- `uas`
- `usb_storage`

---

## ACPI Boot Status Across SC8180XP Devices

Reported on Dell Inspiron 14 3420, Lenovo IdeaPad 5G 14Q8X05:

- ✅ Basic framebuffer
- ✅ USB
- ❌ Keyboard/trackpad (I2C bus not enumerated)
- ❌ PCIe devices (NVMe, WiFi) — even with drivers loaded
- ❌ WiFi, GPU, touch, audio — all dead

Root cause: missing device tree. ACPI alone doesn't properly enumerate the I2C and PCIe buses on this SoC.

---

## The /init Crash — Immediate Fixes to Try

Most likely culprits for dying at /init handoff:

1. **Add `efi=novamap`** to kernel cmdline. This is the #1 known fix for SC8180XP early boot death.
2. **Add `clk_ignore_unused`** if booting with a DT.
3. Verify initramfs contains the root device driver (UFS? NVMe? USB?). ARM64 kernels don't always build in storage drivers.
4. Add `earlycon=efifb` or appropriate earlycon to get early console output and capture the actual error before /init.

---

## The Real Project: Building a Device Tree

No one has contributed a DTS for the Samsung Galaxy Book Go 5G to mainline. The `aarch64-laptops/build` project doesn't list it. No existing ACPI dumps found for this specific device.

### Reference DTs

- `sc8180x.dtsi` — in mainline since 6.5, covers Gen 1 SoC. This is 90% of what's needed.
- `sc8180x-primus.dts` — Gen 1 reference board DTS
- `sc8180x-lenovo-flex-5g.dts` — Gen 1 laptop board DTS
- linux-surface Pro X DT — `https://github.com/linux-surface/surface-pro-x` — working SC8180XP DT
- Konrad Dybcio: "You should be able to do most of the bringup work with sc8180x.dtsi"
- Anton Bambura (jenneron on GitHub) has reportedly poked at SC8180XP specifically

### DTS Structure

```
sc8180x.dtsi (mainline — has CPUs, clocks, pinctrl, I2C/SPI, PCIe, UFS, USB, SMMU, remoteprocs, SPMI)
  └── sc8180xp-samsung-galaxy-book-go5g.dts (YOUR NEW FILE)
        ├── Board-specific I2C devices (from ACPI dump)
        ├── GPIO keys (power button, etc.)
        ├── Panel/display definition
        ├── Touchscreen (I2C addr + interrupt)
        ├── Keyboard (I2C addr + interrupt)
        ├── Touchpad (I2C addr + interrupt)
        ├── WiFi (ath11k PCI address)
        ├── Regulator fixes if needed
        └── Fixed clocks if ACPI provides them
```

---

## Mining Hardware Info from Windows 11

This is how the aarch64-laptops and linux-surface people built their DTs. Windows has all the hardware enumeration — you just need to extract it.

### 1. ACPI Tables (THE BIG ONE)

The DSDT and SSDTs contain: I2C bus definitions, PCIe root complex layout, GPIO pin mappings, clock/regulator references, device _HID/_CID strings.

```powershell
# As Administrator in PowerShell:

# Download acpidump + iasl from https://www.acpica.org/downloads (Windows binary)
# Then dump everything:
acpidump.exe -b          # dumps all tables to binary files
iasl.exe -d DSDT.dat    # disassemble DSDT to ASL source
iasl.exe -d SSDT*.dat   # disassemble all SSDTs
```

The disassembled ASL source is the Rosetta Stone. Every I2C device, its address, its interrupt, its power resource — it's all in there.

### 2. Device Manager (cross-reference)

- View → Resources by Connection → shows interrupts and memory ranges
- Right-click device → Properties → Details → Hardware IDs → gives ACPI path (e.g. `ACPI\QCOM0818`)
- Map ACPI paths to DSDT nodes → map to DTS compatible strings

### 3. PCI Device Enumeration

```powershell
wmic path win32_pnpentity get name,deviceid /format:list
```

Or use MSINFO32 → Components.

### 4. GPIO / Pin Controller

The pinmux is the hardest part. Sources:
- DSDT `_CRS` (Current Resource Settings) for each device
- Windows `devcon` or `pnputil` for enumeration
- SoC TRM (Technical Reference Manual) for fixed pin assignments
- SC8180XP should use `qcom,sc8180xp-tlmm` (may be identical to `qcom,sc8180x-tlmm`)

### 5. Firmware Files

```
# Pull firmware blobs from Windows:
C:\Windows\System32\drivers\   # .sys files may contain embedded firmware
C:\Windows\INF\                 # .inf files reference firmware paths

# Or from the EFI partition:
mountvol S: /s
# Browse S:\EFI\ for Qualcomm .mbn firmware files
```

WiFi/BT firmware (ath11k), ADSP firmware, etc. The linux-surface project packages these for the Surface Pro X — may be reusable.

### 6. UFS Storage

```powershell
Get-Disk | Select-Number,FriendlyName,SerialNumber,Size,PartitionStyle
Get-PhysicalDisk | Format-List
```

Should use same `qcom,sc8180x-ufshc` as Gen 1.

---

## Key Resources

| Resource | URL |
|----------|-----|
| aarch64-laptops build project | https://github.com/aarch64-laptops/build |
| aarch64-laptops IRC | #aarch64-laptops on OFTC (bridged to Matrix) |
| linux-surface Pro X | https://github.com/linux-surface/surface-pro-x |
| linux-surface kernel (spx/ branches) | https://github.com/linux-surface/kernel |
| linux-surface aarch64 configs | https://github.com/qzed/aarch64-kernel-configs |
| linux-surface aarch64 firmware | https://github.com/linux-surface/aarch64-firmware |
| linux-surface aarch64 packages | https://github.com/linux-surface/aarch64-packages |
| Qualcomm mainline status | https://linux-msm.github.io/mainline-status/ |
| Kernel bugzilla SC8180XP | https://bugzilla.kernel.org/show_bug.cgi?id=218512 |
| LKML thread (Feb 2024) | https://lkml.org/lkml/2024/2/22/182 |
| Konrad Dybcio response (Jun 2025) | https://www.spinics.net/lists/linux-arm-msm/msg240437.html |
| Dell Inspiron 3420 SC8180XP report | https://www.spinics.net/linux/fedora/fedora-arm/msg14628.html |
| ACPI dump (IdeaPad 5G) | https://github.com/aarch64-laptops/build/files/14700163/ACPI.zip |
| NVMe-breaking commit | https://github.com/torvalds/linux/commit/8fd4391ee717 |

---

## Quick-Start Path

1. **First:** Add `efi=novamap` to kernel cmdline — this might unblock the /init crash immediately
2. **Capture the error:** `earlycon` or `console=tty0` with `loglevel=7` + photo the screen
3. **Dump ACPI from Windows:** This is the priority — it gives you everything you need for the DTS
4. **Copy `sc8180x-primus.dts`** as a starting point, rename, change compatible
5. **Try booting the Gen 1 DT** — see what works and what's different
6. **Fill in board-specific devices** from the ACPI dump (I2C addresses, interrupts, GPIOs)
7. **Iterate** — boot, fix, repeat

The Gen 1 DT is 90% of what you need. The remaining 10% is board-specific I2C device addresses and GPIO pin assignments that only the ACPI tables can tell you.
