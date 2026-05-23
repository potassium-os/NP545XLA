# NP545XLA — Linux on Samsung Galaxy Book Go 5G

Hardware research, ACPI analysis, and device tree for the Samsung Galaxy Book Go 5G (NP545XLA), powered by the Qualcomm Snapdragon 8cx Gen 2 (SC8180XP).

The build work (kernel, ISO) lives in [NP545XLA-kernel](https://github.com/potassium-os/NP545XLA-kernel). This repo is the hardware reference.

## The Problem

SC8180XP is the only 8cx generation without mainline kernel support. It was explicitly excluded from the Qualcomm/Lenovo/Arm/Linaro aarch64-laptops collaboration that brought up the other 8cx chips. No device tree existed for this laptop. ACPI-only boot gives you basic framebuffer and USB — nothing else.

## What We Found

- **Samsung UEFI only boots ISOs** — raw disk images with GPT ESP are invisible. Must be an El Torito ISO with an appended FAT ESP partition.
- **Ubuntu generic kernel doesn't work** — missing `gcc-sc8180x`, `qnoc-sc8180x`, `rpmhpd`. Everything defers forever in a circular dependency chain.
- **SMMU timeout (-110)** is the root blocker — clocks and power domains never come up without the sc8180x-specific drivers.
- **Serial console is dead** — 3.5mm combo jack with 150KΩ resistor, hardware issue not yet resolved.
- **`nomodeset + break=top` works** — framebuffer is functional, initramfs shell appears. Just no keyboard input yet.

## Status

| Subsystem | Status |
|-----------|--------|
| Custom kernel | 🔧 Building (NP545XLA-kernel repo) |
| Boot ISO | 🔧 Building (NP545XLA-kernel repo) |
| Framebuffer | ✅ Works with nomodeset |
| Initramfs shell | ✅ Works |
| USB keyboard | 🔧 Expected to work with custom kernel |
| UFS storage | 🔧 Expected to work with custom kernel |
| Serial console | ❌ Hardware issue |
| Display | ❌ Not started |
| Keyboard | ❌ Not started |
| Touchpad | ❌ Not started |
| WiFi | ❌ Not started |

## Repository Layout

```
├── README.md              ← you are here
├── docs/
│   ├── overview.md        ← hardware details, serial console, known quirks
│   ├── acpi-analysis.md   ← decoded ACPI: I2C devices, GPIOs, memory ranges
│   ├── dt-boot-plan.md    ← full DT boot strategy and phase plan
│   └── IMG_0172.jpg       ← photo of initramfs boot log (for OCR)
├── dump/
│   ├── NP545XLA-hw-dump/  ← raw ACPI table dumps and disassembly
│   ├── decode-crs.py      ← CRS resource decoder
│   └── ...                ← PowerShell dump scripts (run on Windows)
└── src/
    └── ubuntu-26.04-desktop-arm64.iso  ← Ubuntu arm64 ISO (for initrd fallback)
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

## Related

- [NP545XLA-kernel](https://github.com/potassium-os/NP545XLA-kernel) — custom kernel build (where the actual work happens)
- [Kernel bugzilla #218512](https://bugzilla.kernel.org/show_bug.cgi?id=218512) — SC8180XP support tracking
- [linux-surface Pro X](https://github.com/linux-surface/surface-pro-x) — same SoC, working DT
- [aarch64-laptops](https://github.com/aarch64-laptops/build) — ARM laptop Linux project

## License

GPL-2.0