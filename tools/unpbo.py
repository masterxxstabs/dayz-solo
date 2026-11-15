"""Extracts an uncompressed or LZSS-compressed PBO: unpbo.py <file.pbo> <out_dir>"""
import struct, sys
from pathlib import Path

def cstr(data, pos):
    end = data.index(b"\0", pos)
    return data[pos:end].decode("utf-8", "replace"), end + 1

def lzss(src, size):
    out = bytearray(); i = 0
    while len(out) < size and i < len(src):
        flags = src[i]; i += 1
        for bit in range(8):
            if len(out) >= size or i >= len(src): break
            if flags & (1 << bit):
                out.append(src[i]); i += 1
            else:
                if i + 1 >= len(src): break
                b1, b2 = src[i], src[i + 1]; i += 2
                rpos = len(out) - (b1 | ((b2 & 0xF0) << 4))
                rlen = (b2 & 0x0F) + 3
                for _ in range(rlen):
                    out.append(out[rpos] if 0 <= rpos < len(out) else 0x20); rpos += 1
    return bytes(out[:size])

data = Path(sys.argv[1]).read_bytes(); out_dir = Path(sys.argv[2]).resolve()
pos = 0; entries = []; props = {}
while True:
    name, pos = cstr(data, pos)
    method, orig, _, _, size = struct.unpack_from("<5I", data, pos); pos += 20
    if name == "" and method == 0x56657273:
        while True:
            key, pos = cstr(data, pos)
            if not key: break
            props[key], pos = cstr(data, pos)
        continue
    if name == "": break
    entries.append((name, method, orig, size))
written = 0
for name, method, orig, size in entries:
    blob = data[pos:pos + size]; pos += size
    if method == 0x43707273 or (orig and orig != size):
        blob = lzss(blob, orig)
    target = (out_dir / name.replace("\\", "/")).resolve()
    if out_dir not in target.parents: continue
    target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(blob); written += 1
print("prefix:", props.get("prefix"), "files:", written)
