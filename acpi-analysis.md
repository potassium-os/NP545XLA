# ACPI Dump Analysis — Samsung Galaxy Book Go 5G (NP545XLA)

## What We Got ✅

### DSDT (99,494 lines, 4MB)
- **OEM ID:** QCOMM / SDM8180 (Samsung used the 8180 DSDT — confirms SoC is very close to SC8180X)
- Full ACPI namespace with 171 device nodes
- Disassembled cleanly with iasl

### Other ACPI Tables
- APIC, BGRT, CSRT, DBG2, FACP, FPDT, GTDT, IORT, MCFG, MSDM, PPTT, TPM2, XSDT
- IORT (IOMMU/Interrupt Remapping Table) at 140KB — detailed SMMU topology

### hw-enum.txt (2.5MB)
- Full system info, device enumeration, storage, network, USB, interrupts, firmware paths

### qualcomm-drivers.txt (565+ lines)
- Complete ACPI device ID → Windows driver mapping

---

## Hardware Inventory (from ACPI + Windows)

### SoC
- **Qualcomm Snapdragon 8cx Gen 2 (SC8180XP)**
- ACPI OEM: `SDM8180`, subsystem ID: `CLS08180` / `CLSC8180`

### CPU
- ACPI defines 4x ACPI0007 processor devices (8cx Gen 2 is 8-core: 4x Cortex-A76 + 4x Cortex-A55)
- PPTT table has cache topology

### GPU
- **Qualcomm Adreno 690** (ACPI: `QCOM043A`)
- Windows driver: QCDX (DirectX), inf: `qcdx8180.inf`
- Monitor: **BOE07D3** (BOE panel, 1920x1080, 59Hz)
- Subsystem: `C1A1144D`

### Storage
- **Samsung KLUEG8UHDC-B0E1** — UFS 2.x SSD
- Bus type: UFS (NOT NVMe)
- ACPI UFS controller: `QCOM24A5` (2 instances: UFS0, UFS1)
- This is important: **UFS, not NVMe** — the NVMe commit revert we discussed doesn't apply here

### WiFi
- **Qualcomm QCA639x Wi-Fi 6** (PCI: `VEN_17CB&DEV_1101`)
- ACPI: under `AMSS.QWLN` device, on PCI0.RP1
- Linux driver: **ath11k**

### Bluetooth
- **Qualcomm Bluetooth** (ACPI: `QCOM0471`, UART transport `QCA_SHB\UART_H4`)
- Subsystem: `CLSC8180`
- On UART UR18

### Audio
- **Qualcomm Aqstic** audio codec
- ADSP: `QCOM041D` (Hexagon DSP)
- Slimbus: `QCOM0410` (2 instances)
- Audio codec: `SAMM0821` (Aqstic Audio Adapter)
- Multi-button headset: `SAMM0823`
- ADCM: `SAMM0822` (Aqstic Audio DSP)

### I2C Devices (the critical list for DTS)

| I2C Bus | Device | ACPI Name | _HID | _CID | Function |
|---------|--------|-----------|------|------|----------|
| I2C9 | Keyboard | ECKB | SSEC0001 | PNP0C50 | Samsung embedded controller keyboard (HID over I2C) |
| I2C2 | Touchpad | ECTC | SAM060B | — | Samsung touchpad, subsys C1A1144D |
| I2C1 | Touchscreen | TCPD | SSTP0001 | PNP0C50 | Samsung touchscreen (HID over I2C) |
| I2C6 | SAR sensor 1 | SAR1 | SAMM0209 | — | Proximity sensor |
| IC18 | SAR sensor 2 | SAR2 | SAMM0209 | — | Proximity sensor |

### USB
- USB Role Switch: `QCOM0497`/`QCOM0498` (URS0)
- USB 3.0 host: `USB0` under URS0
- USB Function (device mode): `UFN0` under URS0
- USB 2.0: USB1/UFN1 under URS1
- USB 2.0 (dedicated): USB2 with camera on hub (MP0/MP1/ICAM)
- Type-C: `QCOM04A9`
- XHCI filter: `QCOM04A6`

### Camera
- Under USB2 hub (MP1 → ICAM) — USB-attached camera, not I2C

### Samsung Platform Devices

| _HID | ACPI Name | Function |
|------|-----------|----------|
| SAM0606 | PM3P | Samsung power management |
| SAM0609 | WSAR | WiFi SAR (under AMSS.QWLN, depends on PCI0.RP1) |
| SAM060B | ECTC | Touchpad |
| SAM0101 | SSPN | Samsung platform (controls GPU panel, GPIO) |
| SAM0701 | SAFI | Samsung Firmware Interface (EC communication) |
| SAM0604 | — | Samsung device |
| SAM0605 | — | Samsung device |
| SAM0602 | — | Samsung device |
| SAM0603 | — | Samsung device |
| SAM0426 | SCAI | Samsung Control/Communication Interface |
| SAMM0209 | SAR1/SAR2 | SAR proximity sensors |
| SAMM0611 | LED1 | Samsung LED control |
| SAMM0901 | — | Samsung device |
| SSEC0001 | ECKB | Samsung EC keyboard |
| SSTP0001 | TCPD | Samsung touchscreen |

### Other SoC Peripherals (from ACPI _HIDs)

| _HID | Function |
|------|----------|
| QCOM24A5 | UFS Host Controller (2 instances) |
| QCOM2466 | SD/eMMC Host Controller |
| QCOM0427 | Analog Boot Device? |
| QCOM042E | PMIC regulator? |
| QCOM0430 | PMAP (Power Map?) |
| QCOM042F | PRTC |
| QCOM0263 | PMBM |
| QCOM0419 | PEP0 (Platform Extension Plugin) |
| QCOM040A | BAM (7 instances — Bus Access Manager/DMA) |
| QCOM0418 | UART (4 instances: UR03, UARD, UR18, UR20) |
| QCOM0411 | I2C (11 instances: I2C1,2,5,6,9, IC10,12,15,18,19,20) |
| QCOM040F | SPI (SPI4) |
| QCOM0433 | Reset Power Error Notifier (RPEN) |
| QCOM041B | PILC (Peripheral Image Loader) |
| QCOM0432 | CDI (Crash Dump Injector) |
| QCOM0421 | SCSS |
| QCOM041D | ADSP (Audio DSP) |
| QCOM041E | AMSS (Modem subsystem) |
| QCOM045F | COEX (LTE Coexistence) |
| QCOM0420 | QSM (Service Manager) |
| QCOM0422 | SSDD (Subsystem Dependency) |
| QCOM04AF | Modem thermal limiting |
| QCOM047C | PDSR (Protection Domain Service Registry) |
| QCOM0423 | CDSP (Compute DSP — Hexagon 690) |
| QCOM0499 | SPSS |
| QCOM048B | TFTP |
| QCOM0413 | QDCI (Diagnostic Consumer Interface) |
| QCOM048C | LLC (System Cache) |
| QCOM0409 | SMMU (2 instances: MMU0, MMU1) |
| QCOM049B | IOMMU (2 instances) |
| QCOM043A | GPU0 (Adreno 690) |
| QCOM040B | SCM0 (Secure Channel Manager) |
| QCOM0476 | SCM0/TrEE |
| QCOM040C | SPMI |
| QCOM040D | GIO0 (GPIO) |
| PNP0A08 | PCI0, PCI1, PCI2, PCI3 (4 PCIe root bridges) |
| QCOM04A2 | QPPX (PCIe resource) |
| QCOM040E | IPC0 (Data IPC Router) |
| QCOM048D | Shared Memory Port |
| QCOM0460 | FastRPC |
| QCOM048A | Audio RPC Daemon |
| QCOM0417 | Remote Filesystem |
| QCOM0414 | DiagRouter |
| QCOM0415 | — |
| QCOM0A06 | XHCI filter |
| QCOM0497/0498 | USB Role Switch |
| QCOM04A9 | USB Type-C |

---

## What We Got vs What We Need for DTS

### ✅ Got it
- Full I2C bus topology (which bus, which devices, addresses, _HIDs)
- Keyboard: I2C9, HID SSEC0001 (HID-over-I2C protocol)
- Touchpad: I2C2, HID SAM060B
- Touchscreen: I2C1, HID SSTP0001 (HID-over-I2C)
- WiFi: PCI0.RP1, QCA639x (PCI VEN_17CB&DEV_1101) → ath11k
- BT: UART (UR18), QCOM0471 → qca UART
- GPU: QCOM043A → Adreno 690 → msm drm
- Storage: UFS (not NVMe), QCOM24A5
- Audio: ADSP QCOM041D → Hexagon DSP → audioreach?
- All ACPI _HID values mapped to devices

### ❌ Missing / Needs More Work

1. **I2C device addresses** — The _CRS buffers are encoded in raw ACPI resource descriptors. We need to decode them to extract:
   - I2C slave addresses (7-bit)
   - Interrupt GPIO pin numbers
   - I2C bus speeds
   These are in the binary `_CRS` buffers. We need a script to parse ACPI SerialBus descriptors.

2. **GPIO pin assignments** — The GIO0 references are in _CRS buffers. Need to decode the GpioInt descriptors to get actual pin numbers for interrupts.

3. **Panel/Display timing** — BOE07D3 is the panel ID. We need the panel's mode/refresh/timing data. May need to look up the BOE07D3 panel datasheet or extract from the QCDX driver.

4. **Clock frequencies** — The DSDT has PEP0 (Platform Extension Plugin) clock/voltage dependencies. These map to RPMh resources but the actual frequencies need to come from the SoC DTSI.

5. **Regulator bindings** — PMIC regulators are referenced via SPMI but the actual voltage/current settings are in the Windows driver INFs, not ACPI.

6. **Firmware files** — ath11k firmware, ADSP firmware, modem firmware. We found the Windows driver paths but didn't extract the actual .mbn/.elf files.

7. **Device tree compatible strings** — Need to map ACPI _HIDs to Linux DT compatible strings. Some are obvious (QCOM0411 → qcom,geni-i2c), others need research.

---

## Next Steps

### Immediate (parse the CRS buffers)
Write a script to decode ACPI _CRS resource descriptors from the DSDT. The I2C SerialBus descriptors contain:
- I2C address (7-bit or 10-bit)
- Bus speed (100K, 400K, 1M, 3.4M)
- Controller reference (\_SB.I2Cx)
- GpioInt descriptors contain GPIO pin number, polarity, debounce

### Short-term (build the DTS)
1. Start from `sc8180x.dtsi` + `sc8180x-primus.dts`
2. Add board file: `sc8180xp-samsung-galaxy-book-go5g.dts`
3. Enable I2C1 (touchscreen), I2C2 (touchpad), I2C9 (keyboard)
4. Enable UFS (QCOM24A5 → qcom,sc8180x-ufshc)
5. Enable PCIe0 for WiFi (ath11k PCI)
6. Enable UART for BT
7. Add the BOE07D3 panel node under DSI
8. `clk_ignore_unused` + `efi=novamap` in chosen/stdout

### Medium-term (firmware + audio)
1. Extract ath11k firmware from Windows driver store
2. Extract ADSP firmware
3. Figure out audioreach vs qcom-snd routing
4. USB-C altmode / displayport (if the hardware supports it)
