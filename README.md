# NP545XLA — Linux on Samsung Galaxy Book Go 5G

Bringing mainline Linux to the Samsung Galaxy Book Go 5G (NP545XLA), powered by the Qualcomm Snapdragon 8cx Gen 2 (SC8180XP).

## The Problem

SC8180XP is the only 8cx generation without mainline kernel support. It was explicitly excluded from the Qualcomm/Lenovo/Arm/Linaro aarch64-laptops collaboration that brought up the other 8cx chips. No device tree exists for this laptop. ACPI-only boot gives you basic framebuffer and USB — nothing else.

## The Plan

Build a device tree, boot via GRUB's `devicetree` command, and iterate until we have a usable system. See [docs/dt-boot-plan.md](docs/dt-boot-plan.md) for the full strategy.

**Phase 1:** DT with UART + UFS + USB → get a shell
**Phase 2:** Add keyboard, touchpad, display
**Phase 3:** WiFi, Bluetooth, audio
**Phase 4:** Full system, install to internal storage

## Quick Start

### Prerequisites

- Docker with QEMU user-mode emulation (`sudo apt install qemu-user-static`)
- This repo cloned with submodules (`git clone --recurse-submodules`)

### Build the DTB

```bash
make -C dts
```

### Build the Docker container

```bash
docker build --platform linux/arm64 -t np545xla-build src/
```

### Build the boot ISO

```bash
# With kernel + initrd extracted from Ubuntu arm64 ISO
docker run --platform linux/arm64 --rm --privileged -v "$PWD":/work -v /dev:/dev np545xla-build /work/src/build-img.sh /work/src/ubuntu-26.04-desktop-arm64.iso
```

> **Note:** Samsung UEFI only detects ISOs (El Torito), not raw disk images.

### Flash to USB

```bash
dd if=build/np545xla-boot.iso of=/dev/sdX bs=4M status=progress
```

### Boot

1. Disable Secure Boot in UEFI
2. Insert USB, power on, select USB boot
3. GRUB menu appears with multiple boot options:
   - **DT boot** — loads our device tree, framebuffer console
   - **DT + serial** — DT with serial console (ttyMSM0/ttyS0/ttyAMA0 variants)
   - **DT debug** — serial + `init=/bin/sh` for kernel debugging
   - **ACPI fallback** — no DT, ACPI-only (basic framebuffer + USB)

## Repository Layout

```
├── README.md              ← you are here
├── docs/
│   ├── overview.md        ← hardware details, serial console, known quirks
│   ├── acpi-analysis.md   ← decoded ACPI: I2C devices, GPIOs, memory ranges
│   └── dt-boot-plan.md    ← full DT boot strategy and phase plan
├── dts/
│   ├── sc8180xp-samsung-np545xla.dts  ← board device tree source
│   ├── Makefile                       ← DTB build (uses kernel submodule)
│   └── QUESTIONS.md                   ← open design questions
├── src/
│   ├── Dockerfile         ← arm64 build environment (Ubuntu 26.04)
│   ├── build-img.sh       ← ISO builder (runs in Docker)
│   ├── grub.cfg           ← GRUB config with DT boot entries
│   └── README.md          ← build instructions
├── dump/
│   ├── NP545XLA-hw-dump/  ← raw ACPI table dumps and disassembly
│   ├── decode-crs.py      ← CRS resource decoder
│   └── ...                ← PowerShell dump scripts (run on Windows)
├── submodules/
│   └── linux/             ← mainline kernel (for DTS includes + dtc)
└── build/                 ← output (gitignored)
    └── np545xla-boot.iso
```

## Hardware

| Component | Detail |
|-----------|--------|
| SoC | Qualcomm Snapdragon 8cx Gen 2 (SC8180XP) |
| CPU | 4× Cortex-A76 + 4× Cortex-A55 |
| RAM | 8GB LPDDR4 |
| Storage | 128GB UFS 2.1 |
| Display | BOE07D3 13.3" 1920×1080 IPS |
| WiFi | Qualcomm FastConnect 6800 (ath11k) |
| Debug UART | 3.5mm combo jack (1.8V, 150KΩ resistor on mic sleeve) |

## Current Status

| Subsystem | Status |
|-----------|--------|
| Boot (ACPI) | ✅ Boots to /init, then hangs |
| Boot (DT) | 🔧 Board DTS written, not yet tested |
| Serial console | ❌ No output yet (hardware issue TBD) |
| UFS storage | 🔧 DT node written, not yet tested |
| USB | 🔧 DT nodes written, not yet tested |
| Display | ❌ Not started |
| Keyboard | ❌ Not started |
| Touchpad | ❌ Not started |
| WiFi | ❌ Not started |

## Resources

- [Kernel bugzilla #218512](https://bugzilla.kernel.org/show_bug.cgi?id=218512) — SC8180XP support tracking
- [linux-surface Pro X](https://github.com/linux-surface/surface-pro-x) — same SoC, working DT
- [aarch64-laptops](https://github.com/aarch64-laptops/build) — ARM laptop Linux project
- [Qualcomm mainline status](https://linux-msm.github.io/mainline-status/)

## License

GNU General Public License v2.0 (GPL-2.0) — consistent with the Linux kernel ecosystem this project builds on.
