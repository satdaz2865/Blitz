with open('/Users/macbook/.gemini/antigravity/scratch/vic20-blitz/blitz.prg', 'rb') as f:
    data = f.read()

load_addr = data[0] | (data[1] << 8)
payload = data[2:]
print(f"Total payload length: {len(payload)} bytes, Load addr: {hex(load_addr)}")

ptr = 0
lines = []
while ptr < len(payload) - 4:
    next_line = payload[ptr] | (payload[ptr+1] << 8)
    if next_line == 0:
        print(f"Zero link at offset {ptr} ({hex(load_addr+ptr)})")
        ptr += 2
        break
    line_num = payload[ptr+2] | (payload[ptr+3] << 8)
    eol = payload.find(b'\x00', ptr+4)
    if eol == -1:
        break
    content = payload[ptr+4:eol]
    lines.append((line_num, content))
    ptr = next_line - load_addr
    if ptr < 0 or ptr >= len(payload):
        print(f"Invalid next_line ptr: {hex(next_line)}")
        break

print(f"Parsed {len(lines)} BASIC lines. Last line num: {lines[-1][0] if lines else None}")
print(f"Ended at offset {ptr} of {len(payload)}. Bytes remaining: {len(payload) - ptr}")
if ptr < len(payload):
    print("Remaining bytes sample:", list(payload[ptr:ptr+64]))
