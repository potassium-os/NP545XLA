#!/usr/bin/env python3
"""
Decode ACPI _CRS resource descriptor buffers from dsdt.dsl
Uses ACPICA struct layouts from amlresrc.h for accurate parsing.

Usage: python3 decode-crs.py [path-to-dsdt.dsl]
Output: crs-decoded.txt alongside the input file
"""

import re, sys, struct
from pathlib import Path


def decode_serial_bus(data, desc_start):
    """Decode SerialBus descriptor (0x8E) using ACPICA struct layout.
    
    AML_RESOURCE_SERIAL_COMMON:
      [3]   RevisionId
      [4]   ResSourceIndex
      [5]   Type (0=I2C per ACPICA, but field name says 1=I2C... 
            AML_RESOURCE_I2C_SERIALBUSTYPE=1 in ACPICA)
      [6]   Flags (General)
      [7-8] TypeSpecificFlags (UINT16)
      [9]   TypeRevisionId
      [10-11] TypeDataLength (UINT16)
      [12+]  Type-specific data
    """
    if desc_start + 12 > len(data):
        return "  SerialBus: (buffer too short)"
    
    rev = data[desc_start + 3]
    src_idx = data[desc_start + 4]
    sb_type = data[desc_start + 5]
    gen_flags = data[desc_start + 6]
    ts_flags = struct.unpack_from('<H', data, desc_start + 7)[0]
    ts_rev = data[desc_start + 9]
    ts_data_len = struct.unpack_from('<H', data, desc_start + 10)[0]
    
    type_names = {0: "I2C", 1: "I2C", 2: "UART", 3: "CSI2"}
    # Note: ACPICA uses Type=1 for I2C. Some DSDTs use Type=0.
    # The spec says: 0=I2C, 1=SPI, 2=UART, 3=CSI2
    # But ACPICA defines AML_RESOURCE_I2C_SERIALBUSTYPE=1
    # The actual byte in our DSDT is 0x01 for I2C, matching ACPICA.
    
    if sb_type in (0, 1):  # I2C
        return decode_i2c_serial(data, desc_start, gen_flags, ts_flags, ts_data_len)
    elif sb_type == 2:  # SPI  
        return decode_spi_serial(data, desc_start, gen_flags, ts_flags, ts_data_len)
    elif sb_type == 3:  # UART
        return decode_uart_serial(data, desc_start, gen_flags, ts_flags, ts_data_len)
    else:
        return f"  SerialBus: type={sb_type} (unknown)"


def decode_i2c_serial(data, off, gen_flags, ts_flags, ts_data_len):
    """I2C type-specific: ConnectionSpeed(UINT32) + SlaveAddress(UINT16) + source string"""
    if off + 18 > len(data):
        return "  I2CSerialBus: (buffer too short)"
    
    speed = struct.unpack_from('<I', data, off + 12)[0]
    slave_addr = struct.unpack_from('<H', data, off + 16)[0]
    
    # Source string after type-specific data (12 + ts_data_len)
    src_off = 12 + ts_data_len
    # But ts_data_len is the I2C-specific data length (6 for basic)
    # Actually, ts_data_len includes ConnectionSpeed + SlaveAddress = 6 bytes
    # Source string starts at offset 12 + ts_data_len from desc start? No...
    # The source string starts after the type-specific data.
    # Type-specific data offset from desc_start = 12, length = ts_data_len
    # But we also need to account for vendor data within ts_data_len
    
    # Per ACPI spec, the Resource Source string comes AFTER vendor data
    # Vendor data length = ts_data_len - 6 (6 = I2C min data len)
    # But we can also just scan for the null-terminated string
    
    # Try scanning from after slave address
    src_start = off + 18
    src = ""
    while src_start < len(data) and data[src_start] != 0:
        src += chr(data[src_start])
        src_start += 1
    
    slave_mode = "Slave" if (gen_flags & 0x01) else "ControllerInitiator"
    consumer = "Consumer" if (gen_flags & 0x02) else "Producer"
    addr_mode = "10-bit" if (ts_flags & 0x01) else "7-bit"
    
    speed_str = f"{speed}" if speed < 1000 else f"{speed/1000:.0f}KHz" if speed < 1000000 else f"{speed/1000000:.1f}MHz"
    
    return f"  I2CSerialBus: addr=0x{slave_addr:02X} ({slave_addr}), speed={speed_str}, {addr_mode}, {slave_mode}, {consumer}, controller={src or '(local)'}"


def decode_spi_serial(data, off, gen_flags, ts_flags, ts_data_len):
    if off + 20 > len(data):
        return "  SPISerialBus: (buffer too short)"
    speed = struct.unpack_from('<I', data, off + 12)[0]
    bit_count = data[off + 16]
    slave_select = struct.unpack_from('<H', data, off + 17)[0]
    src_start = off + 19
    src = ""
    while src_start < len(data) and data[src_start] != 0:
        src += chr(data[src_start])
        src_start += 1
    return f"  SPISerialBus: speed={speed}Hz, bits={bit_count}, select=0x{slave_select:02X}, controller={src or '(local)'}"


def decode_uart_serial(data, off, gen_flags, ts_flags, ts_data_len):
    if off + 22 > len(data):
        return "  UARTSerialBus: (buffer too short)"
    speed = struct.unpack_from('<I', data, off + 12)[0]
    rx_len = struct.unpack_from('<H', data, off + 16)[0]
    tx_len = struct.unpack_from('<H', data, off + 18)[0]
    src_start = off + 20
    src = ""
    while src_start < len(data) and data[src_start] != 0:
        src += chr(data[src_start])
        src_start += 1
    return f"  UARTSerialBus: baud={speed}, rx={rx_len}, tx={tx_len}, controller={src or '(local)'}"


def decode_gpio(data, desc_start):
    """Decode GPIO Connection descriptor (0x8C) per ACPICA amlresrc.h.
    
    AML_RESOURCE_GPIO (byte offsets from desc_start):
      [0]    DescriptorType (0x8C)
      [1-2]  Length (UINT16, LE)
      [3]    RevisionId (UINT8)
      [4]    ConnectionType (UINT8) - 0=Interrupt, 1=IO
      [5-6]  Flags (UINT16)
      [7-8]  IntFlags (UINT16) - trigger/polarity for GpioInt
      [9]    PinConfig (UINT8) - 0=default,1=pull-up,2=pull-down,3=no-pull
      [10-11] DriveStrength (UINT16)
      [12-13] DebounceTimeout (UINT16)
      [14-15] PinTableOffset (UINT16) - from byte 0 of this descriptor
      [16]   ResSourceIndex (UINT8)
      [17-18] ResSourceOffset (UINT16) - from byte 0 of this descriptor
      [19-20] VendorOffset (UINT16) - from byte 0 of this descriptor
      [21-22] VendorLength (UINT16)
      [23+]  Pin table, resource source string, vendor data
    """
    if desc_start + 23 > len(data):
        return "  GpioConn: (buffer too short)"
    
    length = struct.unpack_from('<H', data, desc_start + 1)[0]
    rev = data[desc_start + 3]
    conn_type = data[desc_start + 4]  # 0=Interrupt, 1=IO
    flags = struct.unpack_from('<H', data, desc_start + 5)[0]
    int_flags = struct.unpack_from('<H', data, desc_start + 7)[0]
    pin_config = data[desc_start + 9]
    drive_strength = struct.unpack_from('<H', data, desc_start + 10)[0]
    debounce = struct.unpack_from('<H', data, desc_start + 12)[0]
    pin_table_off = struct.unpack_from('<H', data, desc_start + 14)[0]
    src_idx = data[desc_start + 16]
    src_off = struct.unpack_from('<H', data, desc_start + 17)[0]
    vendor_off = struct.unpack_from('<H', data, desc_start + 19)[0]
    vendor_len = struct.unpack_from('<H', data, desc_start + 21)[0]
    
    # Pin count derived from gap between pin table and source string
    # pin_table_off and src_off are from byte 0 of this descriptor
    pin_count = (src_off - pin_table_off) // 2
    
    # Read pins - offsets are from byte 0 of the descriptor (desc_start in the buffer)
    pins = []
    for i in range(pin_count):
        pin_pos = desc_start + pin_table_off + i * 2
        if pin_pos + 1 < len(data):
            pins.append(struct.unpack_from('<H', data, pin_pos)[0])
    
    # Resource source string
    src_pos = desc_start + src_off
    src = ""
    while src_pos < len(data) and data[src_pos] != 0:
        src += chr(data[src_pos])
        src_pos += 1
    
    type_str = "GpioInt" if conn_type == 0 else "GpioIO"
    pull_str = {0: "default", 1: "pull-up", 2: "pull-down", 3: "no-pull"}.get(pin_config, f"0x{pin_config:x}")
    
    trigger = "level" if (int_flags & 0x01) else "edge"
    polarity_map = {0: "active-high", 1: "active-low", 2: "active-both"}
    polarity = polarity_map.get((int_flags >> 1) & 0x03, "unknown")
    sharing = "shared" if (flags & 0x02) else "exclusive"
    
    pin_list = ','.join(str(p) for p in pins)
    extra = f", drive={drive_strength}mA" if drive_strength else ""
    return f"  {type_str}: pins=[{pin_list}], {pull_str}, debounce={debounce}us, {trigger}, {polarity}, {sharing}, controller={src or '(local)'}{extra}"


def decode_interrupt(data, desc_start):
    """Decode Extended Interrupt descriptor (0x89)."""
    length = struct.unpack_from('<H', data, desc_start + 1)[0]
    d = desc_start + 3
    if d + 3 > len(data):
        return "  Interrupt: (buffer too short)"
    
    flags = data[d]
    irq_count = struct.unpack_from('<H', data, d + 1)[0]
    
    irqs = []
    for i in range(irq_count):
        pos = d + 3 + i * 4
        if pos + 3 < len(data):
            irqs.append(struct.unpack_from('<I', data, pos)[0])
    
    trigger = "level" if (flags & 0x01) else "edge"
    polarity = "active-low" if (flags & 0x02) else "active-high"
    sharing = "shared" if (flags & 0x04) else "exclusive"
    wake = ", wake" if (flags & 0x08) else ""
    
    irq_list = ','.join(str(i) for i in irqs)
    return f"  Interrupt: [{irq_list}], {trigger}, {polarity}, {sharing}{wake}"


def decode_memory32_fixed(data, desc_start):
    """Decode Memory32Fixed descriptor (0x86)."""
    d = desc_start + 3
    if d + 12 > len(data):
        return "  Memory32Fixed: (buffer too short)"
    is_write = data[d] & 0x01
    base = struct.unpack_from('<I', data, d + 1)[0]
    size = struct.unpack_from('<I', data, d + 5)[0]
    rw = "RW" if is_write else "RO"
    return f"  Memory32Fixed: base=0x{base:08X}, len=0x{size:08X}, {rw}"


def decode_dword_memory(data, desc_start):
    """Decode DWord Address Space descriptor (0x87)."""
    d = desc_start + 3
    if d + 16 > len(data):
        return "  DWordMemory: (buffer too short)"
    info = data[d]
    base = struct.unpack_from('<I', data, d + 4)[0]
    end = struct.unpack_from('<I', data, d + 8)[0]
    size = struct.unpack_from('<I', data, d + 12)[0]
    rw = "RW" if (info & 0x01) else "RO"
    mem_type = ["Memory", "Reserved", "ACPI", "NVS"][min((info >> 1) & 0x03, 3)]
    return f"  DWordMemory: base=0x{base:08X}, end=0x{end:08X}, len=0x{size:08X}, {rw}, {mem_type}"


def decode_qword_memory(data, desc_start):
    """Decode QWord Address Space descriptor (0x8A)."""
    d = desc_start + 3
    if d + 32 > len(data):
        return "  QWordMemory: (buffer too short)"
    info = data[d]
    base = struct.unpack_from('<Q', data, d + 4)[0]
    end = struct.unpack_from('<Q', data, d + 12)[0]
    size = struct.unpack_from('<Q', data, d + 28)[0]
    rw = "RW" if (info & 0x01) else "RO"
    mem_type = ["Memory", "Reserved", "ACPI", "NVS"][min((info >> 1) & 0x03, 3)]
    return f"  QWordMemory: base=0x{base:016X}, end=0x{end:016X}, len=0x{size:016X}, {rw}, {mem_type}"


def decode_resource_buffer(data, device_path="", hid=""):
    """Walk an ACPI resource buffer and decode each descriptor."""
    lines = [f"\n=== {device_path} (_HID: {hid}) ==="]
    pos = 0
    
    while pos < len(data):
        b = data[pos]
        
        if b & 0x80:
            # Large descriptor
            desc_type = b & 0x7F
            if pos + 2 >= len(data):
                lines.append(f"  (truncated at pos {pos})")
                break
            length = struct.unpack_from('<H', data, pos + 1)[0]
            
            if desc_type == 0x0E:  # SerialBus (0x8E)
                lines.append(decode_serial_bus(data, pos))
            elif desc_type == 0x0C:  # GPIO Connection (0x8C)
                lines.append(decode_gpio(data, pos))
            elif desc_type == 0x09:  # Extended Interrupt (0x89)
                lines.append(decode_interrupt(data, pos))
            elif desc_type == 0x06:  # Memory32Fixed (0x86)
                lines.append(decode_memory32_fixed(data, pos))
            elif desc_type == 0x07:  # DWord Address Space (0x87)
                lines.append(decode_dword_memory(data, pos))
            elif desc_type == 0x0A:  # QWord Address Space (0x8A)
                lines.append(decode_qword_memory(data, pos))
            elif desc_type == 0x08:  # Word Address Space (0x88)
                lines.append(f"  WordAddrSpace: (0x88, len={length})")
            elif desc_type == 0x0B:  # Extended Address Space (0x8B)
                lines.append(f"  ExtendedAddrSpace: (0x8B, len={length})")
            elif desc_type == 0x0D:  # PinFunction (0x8D)
                lines.append(f"  PinFunction: (0x8D, len={length})")
            elif desc_type == 0x0F:  # PinConfig (0x8F)
                lines.append(f"  PinConfig: (0x8F, len={length})")
            elif desc_type == 0x10:  # PinGroup (0x90)
                lines.append(f"  PinGroup: (0x90, len={length})")
            elif desc_type == 0x11:  # PinGroupFunction (0x91)
                lines.append(f"  PinGroupFunction: (0x91, len={length})")
            elif desc_type == 0x12:  # PinGroupConfig (0x92)
                lines.append(f"  PinGroupConfig: (0x92, len={length})")
            else:
                lines.append(f"  LargeDesc: type=0x{desc_type:02X} (0x{b:02X}), len={length}")
            
            pos += 3 + length
        else:
            # Small descriptor
            stype = (b >> 3) & 0x0F
            slen = b & 0x07
            d = pos + 1
            
            if stype == 0x0F:  # End tag
                lines.append("  EndTag")
                break
            elif stype == 0x04:  # IRQ format
                if slen >= 2 and d + 1 < len(data):
                    mask = struct.unpack_from('<H', data, d)[0]
                    irqs = [i for i in range(16) if mask & (1 << i)]
                    irq_list = ','.join(str(i) for i in irqs)
                    lines.append(f"  IRQ: [{irq_list}]")
                else:
                    lines.append(f"  IRQ: (slen={slen})")
            elif stype == 0x08:  # IO Port
                if d + 6 < len(data):
                    decode_f = data[d]
                    min_addr = struct.unpack_from('<H', data, d + 1)[0]
                    max_addr = struct.unpack_from('<H', data, d + 3)[0]
                    lines.append(f"  IOPort: 0x{min_addr:04X}-0x{max_addr:04X}")
                else:
                    lines.append(f"  IOPort: (too short)")
            elif stype == 0x09:  # Fixed IO
                if d + 2 < len(data):
                    addr = struct.unpack_from('<H', data, d)[0]
                    size = data[d + 2]
                    lines.append(f"  FixedIO: 0x{addr:04X}, size={size}")
            elif stype == 0x0A:  # Fixed DMA
                if d + 4 < len(data):
                    req = struct.unpack_from('<H', data, d)[0]
                    chan = struct.unpack_from('<H', data, d + 2)[0]
                    lines.append(f"  FixedDMA: req={req}, chan={chan}")
            else:
                if stype != 0x00:
                    lines.append(f"  SmallDesc: type=0x{stype:X}, len={slen}")
            
            pos += 1 + slen
    
    return '\n'.join(lines)


def main():
    input_path = sys.argv[1] if len(sys.argv) > 1 else "dsdt.dsl"
    input_path = Path(input_path)
    
    if not input_path.exists():
        print(f"File not found: {input_path}")
        sys.exit(1)
    
    output_path = input_path.parent / "crs-decoded.txt"
    
    content = input_path.read_text(encoding='utf-8', errors='replace')
    lines = content.splitlines()
    
    # Track scope stack and last HID for each RBUF
    scope_stack = []
    last_hid = ""
    results = []
    
    rbuf_pattern = re.compile(r'Name\s*\(RBUF,\s*Buffer\s*\((0x[0-9A-Fa-f]+)\)')
    hex_byte = re.compile(r'0x([0-9A-Fa-f]{2})')
    
    for i, line in enumerate(lines):
        # Track Device/Scope nesting
        m = re.match(r'\s*(Device|Scope)\s*\(\s*(\S+)\s*\)', line)
        if m:
            scope_stack.append(m.group(2))
        
        # Track _HID
        m = re.search(r'_HID.*"([^"]+)"', line)
        if m:
            last_hid = m.group(1)
        
        # Find RBUF buffer
        m = rbuf_pattern.search(line)
        if m:
            byte_list = []
            for j in range(i + 1, len(lines)):
                buf_line = lines[j]
                for hb in hex_byte.finditer(buf_line):
                    byte_list.append(int(hb.group(1), 16))
                if '})' in buf_line:
                    break
            
            data = bytes(byte_list)
            device_path = '.'.join(reversed(scope_stack))
            
            decoded = decode_resource_buffer(data, device_path, last_hid)
            results.append(decoded)
    
    with open(output_path, 'w') as f:
        f.write(f"# Decoded ACPI _CRS Resource Buffers\n")
        f.write(f"# Generated from: {input_path.name}\n")
        f.write(f"# Using ACPICA amlresrc.h struct layouts\n\n")
        for r in results:
            f.write(r + '\n')
    
    print(f"Decoded {len(results)} resource buffers -> {output_path}")
    
    # Summary
    i2c_count = sum(1 for r in results if 'I2CSerialBus' in r)
    gpio_count = sum(1 for r in results if 'GpioInt' in r or 'GpioIO' in r)
    int_count = sum(1 for r in results if 'Interrupt:' in r)
    mem_count = sum(1 for r in results if 'Memory' in r)
    print(f"  I2CSerialBus: {i2c_count}")
    print(f"  GPIO:         {gpio_count}")
    print(f"  Interrupt:    {int_count}")
    print(f"  Memory:       {mem_count}")


if __name__ == '__main__':
    main()
