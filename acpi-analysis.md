# ACPI Dump Analysis — Samsung Galaxy Book Go 5G (NP545XLA)

## Device Overview

- **Model:** Samsung Galaxy Book Go 5G (NP545XLA)
- **SoC:** Qualcomm Snapdragon 8cx Gen 2 (SC8180XP)
- **ACPI OEM:** QCOMM / SDM8180 / 0x00000003 (MSFT 5.0 compiler)
- **Subsystem IDs:** CLS08180, CLSC8180, C1A1144D
- **Panel:** BOE07D3 (1920x1080, 59Hz)

### CPU
- 8-core: 4× Cortex-A76 + 4× Cortex-A55 (ACPI defines 4× ACPI0007 devices)
- PPTT table has cache topology

---

## Decoded I2C Devices

All extracted from DSDT _CRS buffers using ACPICA struct layouts (amlresrc.h).

| Device | ACPI | _HID | I2C Addr | Speed | Bus | Function |
|--------|------|------|----------|-------|-----|----------|
| Keyboard | ECKB | SSEC0001 | 0x05 | 400KHz | I2C9 | HID-over-I2C keyboard |
| Touchpad | ECTC | SAM060B | 0x62 | 400KHz | I2C2 | Samsung touchpad |
| Touchscreen | TCPD | SSTP0001 | 0x40 | 400KHz | I2C1 | HID-over-I2C touchscreen/PD |
| SAR sensor 1 | SAR1 | SAMM0209 | 0x20 | 400KHz | I2C6 | Proximity sensor |
| SAR sensor 2 | SAR2 | SAMM0209 | 0x20 | 400KHz | IC18 | Proximity sensor |

All I2C devices: 7-bit addressing, ControllerInitiator mode, Consumer role.

TCPD (SSTP0001) with _CID PNP0C50 is a USB-C PD controller that also provides
touch data via the Samsung touchscreen protocol.

---

## Decoded GPIO Assignments

Extracted from DSDT _CRS GpioInt/GpioIo descriptors on `\_SB.GIO0` (QCOM040D = TLMM).

### GPIO Numbering Warning

The DSDT uses **two different GPIO pin numbering schemes** on the same controller:

1. **GpioIo OperationRegion** (direct GPIO read/write): uses **physical TLMM pin numbers** (0–176). Verified by cross-referencing with the SC8180X pinctrl driver.

2. **GpioInt in _CRS/_AEI** (interrupt source): uses a **Qualcomm-specific namespace** where pins >190 are NOT physical TLMM pins. The Windows "System Manager GPIO" driver (qcgpio.sys) translates these internally. The mapping is opaque without either:
   - Booting Linux with ACPI and reading `/sys/kernel/debug/gpio`
   - Reverse-engineering the Windows GPIO driver

**Physical TLMM pins confirmed via GpioIo OperationRegion:**
- Pin 50 (EAST tile) → LID switch read (LIDR)
- Pin 166 (WEST tile) → Camera enable (CAME)

### GpioInt (from _CRS) — Raw ACPI Pin Numbers

| _HID | ACPI Pin | Pull | Trigger | Polarity | Controller | Likely Function |
|------|----------|------|---------|----------|------------|-----------------|
| SSEC0001 | 640 | pull-up | edge | active-low | \_SB.GIO0 | Keyboard IRQ |
| SAM060B | 118 | pull-up | level | active-low | \_SB.GIO0 | Touchpad IRQ |
| SSTP0001 | 448 | pull-up | edge | active-low | \_SB.GIO0 | Touchscreen IRQ |
| SAMM0209 | 93 | default | edge | active-low | \_SB.GIO0 | SAR1 IRQ |
| SAMM0209 | 87 | default | edge | active-low | \_SB.GIO0 | SAR2 IRQ |
| QCOM0418 | 129 | pull-down | level | active-low | \_SB.GIO0 | UART IRQ |
| QCOM0418 | 86 | pull-down | level | active-low | \_SB.GIO0 | UART IRQ |
| QCOM0418 | 46 | pull-down | level | active-low | \_SB.GIO0 | UART IRQ |
| QCOM0418 | 30 | pull-down | level | active-low | \_SB.GIO0 | UART IRQ |
| QCOM041D | 256 | pull-down | level | active-high | \_SB.GIO0 | ADSP IRQ |
| QCOM0476 | 9 | pull-up | level | active-low | \_SB.GIO0 | TrEE IRQ |
| QCOM040D | 189 | pull-down | level | active-both | \_SB.GIO0 | TLMM LID event (PLST≠1) |
| QCOM040D | 320 | no-pull | level | active-both | \_SB.GIO0 | TLMM LID event (PLST==1) |
| PNP0A08 | 448 | pull-up | level | active-low | \_SB.GIO0 | PCIe0 hot-plug |
| PNP0A08 | 512 | pull-up | level | active-low | \_SB.GIO0 | PCIe1 hot-plug |
| PNP0A08 | 576 | pull-up | level | active-low | \_SB.GIO0 | PCIe2 hot-plug |

**Pins ≤189** are likely 1:1 with physical TLMM pins (within ACPI ngpios=190 range).
**Pins >189** require translation — cannot be mapped to TLMM pins from DSDT alone.

For DT: touchpad IRQ pin 118 and SAR pins 93, 87 can be used directly.
Keyboard (640), touchscreen (448), ADSP (256) pins need translation via Linux boot.

### GpioIO (from _CRS) — Raw ACPI Pin Numbers

| _HID | ACPI Pin | Pull | Controller | Function |
|------|----------|------|------------|----------|
| QCOM041D | 143 | no-pull | \_SB.GIO0 | ADSP SPI CS? |
| QCOM041D | 165 | pull-down | \_SB.GIO0 | ADSP reset? |
| QCOM040D | 96 | pull-up | \_SB.GIO0 | SD card detect |
| QCOM04A2 | 35 | no-pull | \_SB.GIO0 | QPPX GPIO 0 |
| QCOM04A2 | 175 | no-pull | \_SB.GIO0 | QPPX GPIO 1 |
| QCOM04A2 | 102 | no-pull | \_SB.GIO0 | QPPX GPIO 2 |
| QCOM04A2 | 178 | no-pull | \_SB.GIO0 | QPPX GPIO 3 |
| SAM0101 | 25 | no-pull | \_SB.GIO0 | SSPN GPIO 0 |
| SAM0101 | 130 | no-pull | \_SB.GIO0 | SSPN GPIO 1 |
| SAM0602 | 677 | no-pull | \_SB.PM01 | PMIC GPIO |
| SAM0602 | 528 | no-pull | \_SB.PM01 | PMIC GPIO |

---

## Storage

- **Samsung KLUEG8UHDC-B0E1** — UFS 2.x
- UFS controller: QCOM24A5 (2 instances: UFS0, UFS1)
- **UFS, not NVMe** — the NVMe commit revert (8fd4391ee717) is irrelevant
- SDC2 (QCOM2466) — SD card reader

---

## WiFi & Bluetooth

### WiFi
- **QCA639x Wi-Fi 6** (PCI: VEN_17CB&DEV_1101)
- ACPI: under AMSS.QWLN, on PCI0.RP1
- Linux driver: **ath11k** (PCI bus)
- WiFi SAR: SAM0609 under AMSS.QWLN

### Bluetooth
- **Qualcomm Bluetooth** (QCOM0471, UART H4)
- On UART UR18
- Linux driver: **qca** (UART)

---

## GPU & Display

- **Adreno 690** (QCOM043A)
- Windows driver: QCDX (qcdx8180.inf)
- Panel: BOE07D3 (1920×1080, 59Hz)
- DSI or DP interface — TBD (need to check DSI/DP topology)

---

## Audio

- **ADSP** (QCOM041D) — Hexagon DSP, SPI + GpioInt
- Slimbus: QCOM0410 (2 instances)
- Aqstic codec: SAMM0821
- Multi-button headset: SAMM0823
- ADCM: SAMM0822
- Linux: audioreach / qcom-snd routing TBD

---

## USB

- USB Role Switch: QCOM0497/QCOM0498 (URS0/URS1)
- USB 3.0 host: USB0 under URS0
- USB 2.0: USB1/UFN1 under URS1, USB2 (dedicated, with camera hub)
- Type-C: QCOM04A9
- XHCI filter: QCOM04A6

---

## PCIe

4 root bridges (PNP0A08): PCI0–PCI3
- PCI0: WiFi (QCA639x) on RP1
- PCI1–PCI3: TBD (possibly NVMe on other SKUs, unpopulated here)
- QPPX (QCOM04A2): PCIe resource controller

---

## I2C Bus Topology

11 I2C controllers (QCOM0411):
I2C1, I2C2, I2C5, I2C6, I2C9, IC10, IC12, IC15, IC18, IC19, IC20

Populated buses:
- I2C1 → Touchscreen (TCPD/SSTP0001 @ 0x40) + POWR device
- I2C2 → Touchpad (ECTC/SAM060B @ 0x62)
- I2C6 → SAR1 (SAMM0209 @ 0x20)
- I2C9 → Keyboard (ECKB/SSEC0001 @ 0x05) + LID0
- IC18 → SAR2 (SAMM0209 @ 0x20)

---

## UART

4 UART controllers (QCOM0418): UR03, UARD, UR18, UR20
- UR18 → Bluetooth (QCOM0471)

---

## SPI

1 SPI controller (QCOM040F): SPI4
- ADSP (QCOM041D) uses SPI

---

## Samsung Platform Devices

| _HID | ACPI | Function |
|------|------|----------|
| SAM0606 | PM3P | Power management |
| SAM0609 | WSAR | WiFi SAR control |
| SAM060B | ECTC | Touchpad |
| SAM0101 | SSPN | Platform control (GPU panel, GPIO) |
| SAM0701 | SAFI | Firmware Interface (EC) |
| SAM0604 | — | Samsung device |
| SAM0605 | — | Samsung device |
| SAM0602 | MCTL | Multi-function control |
| SAM0426 | SCAI | Control/Communication Interface |
| SAMM0209 | SAR1/2 | SAR proximity sensors |
| SAMM0611 | LED1 | LED control |
| SSEC0001 | ECKB | EC keyboard |
| SSTP0001 | TCPD | Touchscreen/PD |

---

## Other SoC Peripherals

| _HID | Function |
|------|----------|
| QCOM24A5 | UFS Host Controller |
| QCOM2466 | SD/eMMC Host Controller |
| QCOM0419 | PEP0 (Platform Extension Plugin — clock/voltage deps) |
| QCOM040A | BAM (7 instances — Bus Access Manager/DMA) |
| QCOM0418 | UART (4 instances) |
| QCOM0411 | I2C (11 instances) |
| QCOM040F | SPI |
| QCOM040D | GIO0 (TLMM GPIO controller) |
| QCOM0433 | RPEN (Reset Power Error Notifier) |
| QCOM041B | PILC (Peripheral Image Loader) |
| QCOM0432 | CDI (Crash Dump Injector) |
| QCOM041D | ADSP (Audio DSP) |
| QCOM041E | AMSS (Modem subsystem) |
| QCOM045F | COEX (LTE Coexistence) |
| QCOM0420 | QSM (Service Manager) |
| QCOM0423 | CDSP (Compute DSP — Hexagon 690) |
| QCOM0499 | SPSS |
| QCOM048B | TFTP |
| QCOM048C | LLC (System Cache) |
| QCOM0409 | SMMU (2 instances) |
| QCOM043A | GPU (Adreno 690) |
| QCOM040B | SCM0 (Secure Channel Manager) |
| QCOM0476 | TrEE (Trusted Execution Environment) |
| QCOM040C | SPMI |
| QCOM040E | IPC0 (Data IPC Router) |
| QCOM0460 | FastRPC |
| QCOM0417 | Remote Filesystem |
| QCOM0408 | QDSS (Debug/Trace) |
| QCOM0430 | PMAP (Power Map) |
| QCOM042F | PRTC |
| QCOM0263 | PMBM |

---

## Data Sources

- `dsdt.dsl` — Disassembled DSDT (99,494 lines), from `iasl -d dsdt.dat`
- `hw-enum.txt` — Full system enumeration (2.5MB)
- `qualcomm-drivers.txt` — ACPI HID → Windows driver mapping
- `crs-decoded.txt` — Decoded _CRS resource buffers (77 devices)
- `decode-crs.py` — Python decoder using ACPICA amlresrc.h struct layouts
- `NP545XLA-HardwareEnum.ps1` — PowerShell hardware enumeration script
- `NP545XLA-ReDisasm.ps1` — iasl -e re-disassembly script

---

## DTS Build Status

### Ready to Use
- I2C topology + addresses (keyboard, touchpad, touchscreen, SAR)
- UFS storage configuration
- WiFi (PCI, ath11k)
- Bluetooth (UART, qca)
- GPU (Adreno 690, msm drm)
- ADSP (QCOM041D)
- Physical TLMM GPIOs from GpioIo: pin 50 (LID), pin 166 (camera)

### Needs Translation (ACPI GPIO pins >190)
- Keyboard IRQ (ACPI pin 640 → physical TLMM pin unknown)
- Touchscreen IRQ (ACPI pin 448 → physical TLMM pin unknown)
- ADSP IRQ (ACPI pin 256 → physical TLMM pin unknown)
- PCIe hot-plug IRQs (pins 448, 512, 576)

### Needs Research
- Panel timing (BOE07D3)
- PMIC regulator bindings
- Firmware blobs (ath11k, ADSP, modem)
- Audio routing (audioreach vs qcom-snd)
- DSI vs DP interface for panel
- USB-C altmode / DisplayPort

### Boot Parameters (known from linux-surface Pro X)
- `efi=novamap` — required, fixes /init crash on SC8180XP
- `clk_ignore_unused` — required for DT boot (keeps clocks on that ACPI would manage)

### Reference DTs
- `sc8180x.dtsi` — SoC base (in mainline since 6.5)
- `sc8180x-primus.dts` — Qualcomm reference laptop
- `sc8180x-lenovo-flex-5g.dts` — Lenovo Flex 5G (same SoC)
- linux-surface Pro X — custom DSDT override + kernel patches
