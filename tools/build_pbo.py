"""Packs a folder into an uncompressed DayZ PBO.

Usage: python build_pbo.py <source_dir> <output.pbo> <prefix>
"""
import hashlib
import struct
import sys
import time
from pathlib import Path


def entry_header(name: bytes, method: int, size: int, timestamp: int) -> bytes:
    return name + b"\0" + struct.pack("<5I", method, 0, 0, timestamp, size)


def build(source: Path, output: Path, prefix: str) -> None:
    files = sorted(p for p in source.rglob("*") if p.is_file())
    now = int(time.time())

    header = bytearray(entry_header(b"", 0x56657273, 0, 0))
    header += b"prefix\0" + prefix.encode() + b"\0\0"

    data = bytearray()
    for path in files:
        content = path.read_bytes()
        name = str(path.relative_to(source)).replace("/", "\\").encode()
        header += entry_header(name, 0, len(content), now)
        data += content
    header += entry_header(b"", 0, 0, 0)

    body = bytes(header + data)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(body + b"\0" + hashlib.sha1(body).digest())
    print(f"Packed {len(files)} files into {output}")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    build(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3])
