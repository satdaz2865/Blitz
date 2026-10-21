lines = [
    [234,234,234,169,0,141,132,3,169,127,141,34,145,173,17,145,201,126,240,9],
    [201,62,240,5,169,1],
    [141,132,3,169,255,141,34,145,173,197,0,201,64,240,5,169,1,141,132,3,169,0,141],
    [131,3,162,0,189,206,31,201,32,240,5,169,1,141,131,3,232,224,21,208,239],
    [173,130,3,201,33,240,13,173,24,30,201,96,240,1,0,169,33,141,130,3,96]
]
mc = []
for l in lines:
    mc.extend(l)

opcodes = {
    0xEA: ('NOP', 1),
    0xA9: ('LDA #${:02X}', 2),
    0x8D: ('STA ${:04X}', 3),
    0xAD: ('LDA ${:04X}', 3),
    0xC9: ('CMP #${:02X}', 2),
    0xF0: ('BEQ +{:d}', 2),
    0xD0: ('BNE +{:d}', 2),
    0xA2: ('LDX #${:02X}', 2),
    0xBD: ('LDA ${:04X},X', 3),
    0xE8: ('INX', 1),
    0xE0: ('CPX #${:02X}', 2),
    0x60: ('RTS', 1),
    0x00: ('BRK', 1)
}

pc = 7235
i = 0
while i < len(mc):
    op = mc[i]
    if op in opcodes:
        name, length = opcodes[op]
        if length == 1:
            print(f"{pc+i:04X}: {name}")
        elif length == 2:
            val = mc[i+1]
            if 'BEQ' in name or 'BNE' in name:
                rel = val if val < 128 else val - 256
                print(f"{pc+i:04X}: {name.split()[0]} {pc+i+2+rel:04X}")
            else:
                print(f"{pc+i:04X}: " + name.format(val))
        elif length == 3:
            addr = mc[i+1] | (mc[i+2] << 8)
            print(f"{pc+i:04X}: " + name.format(addr))
        i += length
    else:
        print(f"{pc+i:04X}: .byte 0x{op:02X}")
        i += 1
