# DT Boot Plan — Samsung Galaxy Book Go 5G (NP545XLA)

## Strategy Overview

Boot the NP545XLA with a custom device tree via GRUB's `devicetree` command on a modified Ubuntu 26.04 ISO. The approach: start minimal (get a shell), then iterate.

---

## 1. Device Tree

### What Already Exists

| Resource | Status | What It Gives Us |
|----------|--------|-----------------|
| `sc8180x.dtsi` (mainline, since 6.5) | ✅ In-tree | SoC-level: CPUs, clocks, pinctrl, I2C/SPI, PCIe, UFS, USB, SMMU, remoteprocs, interconnects, QUP engines |
| `sc8180x-primus.dts` | ✅ In-tree | Gen 1 reference board — starting template |
| `sc8180x-lenovo-flex-5g.dts` | ✅ In-tree | Gen 1 laptop — closer to our form factor |
| linux-surface Pro X DT | ✅ `linux-surface/kernel` spx/ branch | **Same SoC (SC8180XP)** — working DT for Surface Pro X. The Rosetta Stone. |
| Our ACPI dumps | ✅ In repo | I2C devices, GPIOs, memory ranges, interrupts — board-specific data the DT needs |

### The Key Insight

SC8180XP is the 'P' variant of SC8180X ("no integrated modem"). Konrad Dybcio says the SoC dtsi should be nearly identical. The board DTS is where all the Samsung-specific stuff lives.

### DT Structure

```
sc8180x.dtsi                    (mainline — DON'T TOUCH, use as-is)
  └── sc8180xp.dtsi             (NEW — minimal diff from sc8180x: remove modem, fix any P-variant diffs)
        └── sc8180xp-samsung-np545xla.dts  (NEW — board file)
```

### What Goes In `sc8180xp.dtsi`

- Include `sc8180x.dtsi`
- Remove/override the integrated modem node (the 'P' difference)
- Any clock or interconnect differences (if any — likely none visible to SW)

### What Goes In the Board DTS

**Phase 1 — Get a shell (minimal viable DT):**
- `/` model + compatible string
- Memory node (8GB LPDDR4 — should be autodetected, but confirm)
- QUP1 SE10 UART at 0xA90000 (console — `stdout-path`)
- UFS storage at 0x01D84000 (boot from internal flash)
- USB (boot from USB stick as fallback)
- Pinctrl for the above
- `chosen` node with `stdout-path = "serial0:115200n8"`

**Phase 2 — Input & display:**
- I2C1 + touchscreen (SSTP0001, addr 0x40, IRQ pin 448→needs translation)
- I2C2 + touchpad (SAM060B, addr 0x62, IRQ pin 118)
- I2C9 + keyboard (SSEC0001, addr 0x05, IRQ pin 640→needs translation)
- Display/panel (BOE07D3, 1920x1080) — MDSS + DSI

**Phase 3 — Full bringup:**
- WiFi (ath11k PCIe)
- Bluetooth
- Audio (ADSP)
- SAR sensors
- Suspend/resume

### GPIO Pin Translation (the hard part)

From the ACPI analysis, pins ≤189 map 1:1 to physical TLMM. Pins >189 (keyboard 640, touchscreen 448, ADSP 256, PCIe hot-plug pins) need translation via either:
1. Booting Linux with ACPI and reading `/sys/kernel/debug/gpio`
2. Reverse-engineering qcgpio.sys
3. Cross-referencing with the Surface Pro X DT (same SoC, similar board design)

**Strategy:** The Surface Pro X DT likely has the same QUP/GPIO topology. Cross-reference their working pin assignments with our ACPI data.

---

## 2. Boot Media Strategy

### Option A: Modify Ubuntu 26.04 ISO (RECOMMENDED for Phase 1)

This is the lowest-effort path. Ubuntu's aarch64 ISO already boots on this device (in ACPI mode). We just need GRUB to load our DTB instead.

**Steps:**
1. Download `ubuntu-26.04-desktop-arm64.iso`
2. Extract, modify, repack:
   ```bash
   # Extract
   mkdir iso-mod && cd iso-mod
   7z x ../ubuntu-26.04-desktop-arm64.iso

   # Add our DTB
   mkdir -p boot/dtb/qcom
   cp sc8180xp-samsung-np545xla.dtb boot/dtb/qcom/

   # Edit GRUB config to add our boot entry
   # (see GRUB config below)
   ```

3. Repack as ISO or flash to USB directly as a partition

**GRUB config addition** (add to `boot/grub/grub.cfg` or the EFI partition's grub.cfg):
```
menuentry 'Ubuntu 26.04 (NP545XLA DT)' {
    devicetree /boot/dtb/qcom/sc8180xp-samsung-np545xla.dtb
    linux   /casper/vmlinuz efi=novamap clk_ignore_unused console=tty0 loglevel=8 initcall_debug
    initrd  /casper/initrd
}
```

**Pros:** Minimal effort, known-good base, casper/live environment gives a full Ubuntu desktop for testing

**Cons:** Ubuntu's stock kernel may not have all QCOM drivers built as modules in the initramfs; modifying ISOs can be finicky; UEFI Secure Boot must be off (required anyway for `devicetree` command)

### Option B: Build a Custom Image with `aarch64-arch-mkimg` (RECOMMENDED for Phase 2+)

This is what linux-surface uses for the Surface Pro X. It builds an Arch Linux ARM image with the custom kernel, firmware, and DTB pre-installed.

**Steps:**
1. Fork `linux-surface/aarch64-arch-mkimg`
2. Add our board DT and kernel config
3. Build: `sudo ./mkimg.sh default` → produces a raw disk image
4. `dd` to USB stick

**Pros:** Full control over kernel config, initramfs contents, and firmware; proven workflow for this exact SoC family; Arch's kernel package system makes iteration fast

**Cons:** Arch-based (if you wanted Ubuntu); more upfront setup; needs an aarch64 build environment or QEMU

### Option C: Build Ubuntu Image from Scratch

Use `livecd-rootfs` or `ubuntu-image` to build a custom Ubuntu aarch64 image with our kernel and DTB baked in. This is what Canonical does for their official ARM images.

**Pros:** Pure Ubuntu 26.04; proper apt-based system

**Cons:** Heavy tooling; slow; overkill for Phase 1

### Option D: Direct USB Stick with Manual GRUB Install (QUICKEST for pure iteration)

Skip the ISO entirely. Format a USB stick with an EFI System Partition, install GRUB for aarch64, drop in a kernel + initramfs + DTB, boot.

**Steps:**
```bash
# On a Linux host with grub-efi-arm64 installed:
# (or use a pre-built GRUB EFI binary from linux-surface/grub-image-aarch64)

# Partition USB: 1GB EFI System Partition, rest ext4 rootfs
parted /dev/sdX mklabel gpt
parted /dev/sdX mkpart ESP fat32 1MiB 1GiB
parted /dev/sdX mkpart root ext4 1GiB 100%
parted /dev/sdX set 1 esp on

# Format and mount
mkfs.vfat -F32 /dev/sdX1
mkfs.ext4 /dev/sdX2
mount /dev/sdX2 /mnt
mkdir -p /mnt/boot/efi
mount /dev/sdX1 /mnt/boot/efi

# Install minimal rootfs (debootstrap or extract Ubuntu base tarball)
# ... or just put a casper/initrd from the ISO on it

# Install GRUB
grub-install --target=arm64-efi --efi-directory=/mnt/boot/efi --removable

# Add our files
mkdir -p /mnt/boot/dtb/qcom
cp vmlinuz /mnt/boot/
cp initrd.img /mnt/boot/
cp sc8180xp-samsung-np545xla.dtb /mnt/boot/dtb/qcom/

# Write grub.cfg
cat > /mnt/boot/efi/EFI/BOOT/grub.cfg << 'EOF'
menuentry 'NP545XLA DT Boot' {
    devicetree /boot/dtb/qcom/sc8180xp-samsung-np545xla.dtb
    linux /boot/vmlinuz efi=novamap clk_ignore_unused console=tty0 loglevel=8 initcall_debug root=/dev/sda2 rootwait
    initrd /boot/initrd.img
}
EOF
```

**Pros:** Fastest iteration cycle — just swap kernel/DTB on the USB and reboot; no ISO repacking; full control

**Cons:** No installer, no live desktop; needs a pre-built rootfs; manual setup

### **Recommendation: Option D for Phase 1, Option B for Phase 2+**

Option D gets you booting fastest. Once the DT is stable, switch to a proper image build for daily driving.

---

## 3. Kernel

### Build vs Stock

Ubuntu 26.04 ships kernel 6.14+ (or 6.15). The `sc8180x.dtsi` has been in-tree since 6.5. But:

- **No `sc8180xp` compatible** exists in mainline yet — the DT won't match any built-in platform drivers
- **QUP GENI earlycon** should work on stock kernel (driver is mainline)
- **UFS, USB, I2C, pinctrl** all have mainline SC8180X support

**Phase 1:** Try stock Ubuntu kernel first. If it works with our DT, great. The only thing we're adding is the board DTS — all the drivers are already there.

**Phase 2+** (if stock has gaps): Build a custom kernel based on `linux-surface/kernel` spx/ branch, which already has SC8180XP-specific patches.

### Required Kernel Config Options

```
# Serial console
CONFIG_SERIAL_QCOM_GENI=y
CONFIG_SERIAL_QCOM_GENI_CONSOLE=y
CONFIG_SERIAL_EARLYCON=y
CONFIG_SERIAL_QCOM_GENI_EARLYCON=y

# UFS
CONFIG_SCSI_UFS_QCOM=y
CONFIG_SCSI_UFSHCD=y
CONFIG_SCSI_UFSHCD_PLATFORM=y

# USB (for boot from USB stick)
CONFIG_USB_DWC3=y
CONFIG_USB_DWC3_QCOM=y
CONFIG_PHY_QCOM_QMP=y
CONFIG_PHY_QCOM_SNPS_FEMTO_V2=y
CONFIG_USB_STORAGE=y
CONFIG_USB_UAS=y

# I2C (keyboard, touchpad, touchscreen)
CONFIG_I2C_QCOM_GENI=y
CONFIG_I2C_HID_OF=y

# Pin controller
CONFIG_PINCTRL_SM8150=y        # SC8180X uses SM8150 pinctrl driver
CONFIG_PINCTRL_QCOM_SPMI_PMIC=y

# Display
CONFIG_DRM_MSM=y
CONFIG_DRM_PANEL_SIMPLE=y
CONFIG_FB=y
CONFIG_FRAMEBUFFER_CONSOLE=y

# Interconnect (required for QCOM bus scaling)
CONFIG_INTERCONNECT_QCOM_SC8180X=y

# Clocks
CONFIG_COMMON_CLK_QCOM=y
CONFIG_SC_GCC_8180X=y
CONFIG_SC_DISPCC_8180X=y
CONFIG_SC_GPUCC_8180X=y
CONFIG_SC_VIDEOCC_8180X=y

# SPMI (PMIC comms)
CONFIG_QCOM_SPMI_ADC5=y
CONFIG_QCOM_SPMI_RRADC=y

# Regulators
CONFIG_REGULATOR_QCOM_RPMH=y

# PCIe (WiFi)
CONFIG_PCIE_QCOM=y
CONFIG_PCI_HOST_GENERIC=y

# Remoteproc (ADSP, etc.)
CONFIG_QCOM_Q6V5_ADSP=y
CONFIG_QCOM_Q6V5_MSS=y

# ath11k WiFi
CONFIG_ATH11K=y
CONFIG_ATH11K_PCI=y
```

### Initramfs Must Include

For USB boot:
```
phy-qcom-qmp
phy-qcom-snps-femto-v2
dwc3-qcom
uas
usb_storage
```

For UFS boot:
```
ufs_qcom
ufshcd-platform
```

---

## 4. Boot Flow

```
UEFI firmware
  → GRUB (on USB ESP or internal EFI partition)
    → GRUB `devicetree` command loads our DTB
    → GRUB `linux` loads kernel with cmdline
    → GRUB `initrd` loads initramfs
  → Kernel boots with DT (not ACPI)
    → earlycon on qcom_geni UART (if serial is working)
    → Pinctrl, clocks, interconnects come up
    → UFS/USB rootfs mounted
    → /init → shell / desktop
```

**Critical cmdline params:**
```
efi=novamap clk_ignore_unused console=tty0 loglevel=8
```

- `efi=novamap` — **mandatory**, prevents boot lockups on SC8180XP
- `clk_ignore_unused` — **mandatory for DT boot**, prevents unused clock shutdown → lockup
- `console=tty0` — framebuffer console (no serial yet)
- `loglevel=8` — see everything

**For init debugging:**
```
init=/bin/sh    # skip init, go straight to shell — highest-signal test
panic=30        # reboot on panic after 30s
initcall_debug  # show every initcall
```

---

## 5. Phase Plan

### Phase 0: Prepare Boot Media (Day 1)

- [ ] Build DTB from board DTS (start with minimal: chosen + UART + UFS + USB)
- [ ] Prepare USB stick (Option D: ESP + rootfs + GRUB + kernel + DTB)
- [ ] Disable Secure Boot in UEFI
- [ ] First boot attempt

### Phase 1: Get a Shell (Day 1-3)

- [ ] Boot with `init=/bin/sh` — does kernel come up?
- [ ] If yes: rootfs mounting works, init is the issue
- [ ] If no: check `initcall_debug` output on screen, find which probe hangs
- [ ] Iterate on DT (add missing clocks, regulators, interconnects)
- [ ] Goal: `root=/dev/sda2 init=/bin/sh` gives a working shell

### Phase 2: Input + Display (Week 1)

- [ ] Add keyboard (I2C9, SSEC0001)
- [ ] Add touchpad (I2C2, SAM060B)
- [ ] Add display panel (BOE07D3 via MDSS/DSI)
- [ ] Add USB keyboard/mouse as fallback
- [ ] Goal: usable desktop with input

### Phase 3: Connectivity (Week 2)

- [ ] WiFi via ath11k (PCIe)
- [ ] Bluetooth
- [ ] Goal: network access, apt update works

### Phase 4: Full System

- [ ] Audio (ADSP remoteproc)
- [ ] SAR sensors
- [ ] Suspend/resume
- [ ] Install to internal UFS (not USB)
- [ ] Switch to Option B image build for daily driver

---

## 6. The Surface Pro X DT — Our Secret Weapon

The linux-surface Pro X kernel (`spx/` branch) has a **working SC8180XP device tree**. Same SoC, same QUP layout, same pinctrl driver. The differences are board-level:

| Component | Surface Pro X | NP545XLA |
|-----------|--------------|----------|
| Panel | Surface display | BOE07D3 1080p |
| Keyboard | Surface Type Cover | I2C9 SSEC0001 |
| Touchpad | Surface Type Cover | I2C2 SAM060B |
| WiFi | Same ath11k | Same ath11k |
| Storage | NVMe | UFS |

**Action items:**
1. Clone `linux-surface/kernel` and find the SPX DT files in `arch/arm64/boot/dts/qcom/`
2. Diff their DT against mainline `sc8180x-primus.dts` to see what's SC8180XP-specific
3. Use their DT as the base, swap in our board-specific I2C devices and GPIOs from the ACPI dump
4. This eliminates 90% of the "does the QUP come up" debugging

---

## 7. Open Questions

1. **Does the NP545XLA UEFI support the GRUB `devicetree` command?** — It should; this is standard EFI boot. But the UEFI might not pass the DTB correctly. The Surface Pro X works this way, so odds are good.
2. **UFS vs NVMe** — Our device uses UFS, not NVMe. The mainline `sc8180x.dtsi` has the UFS node. This should "just work" with the right compatible string.
3. **Firmware files** — ath11k WiFi needs firmware blobs. The linux-surface `aarch64-firmware` repo may have them. Otherwise, extract from Windows.
4. **Display without serial** — Without a serial console, we're flying blind on early boot failures. The framebuffer console is our only visibility. If the kernel hangs before fbcon comes up, we see nothing. Consider: can we get `pstore` or `ramoops` working for post-mortem?
5. **GPIO pin translation** — The ACPI GpioInt pins >189 are opaque. We need either an ACPI boot to read `/sys/kernel/debug/gpio`, or the Surface Pro X DT to cross-reference.

---

## 8. File Structure in Repo

```
thehonker/NP545XLA/
├── dt/                                    # DT work
│   ├── sc8180xp.dtsi                      # SoC overlay
│   ├── sc8180xp-samsung-np545xla.dts      # Board DTS
│   └── Makefile                           # dtc build helper
├── boot/                                  # Boot media
│   ├── grub.cfg                           # GRUB config
│   └── build-usb.sh                       # Script to prepare USB stick
├── kernel/                                # Kernel config
│   └── config-np545xla                    # .config fragment
├── NP545XLA-hw-dump/                      # (existing) ACPI data
├── overview.md                            # (existing)
├── acpi-analysis.md                       # (existing)
└── dt-boot-plan.md                        # This file
