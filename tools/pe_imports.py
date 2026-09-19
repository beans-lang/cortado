#!/usr/bin/env python3
"""Print the DLLs a PE binary imports, and whether each sits beside it.

STATUS_ENTRYPOINT_NOT_FOUND and STATUS_DLL_NOT_FOUND say a Windows binary died
in the loader without reaching main, and neither says which import was at fault.
This reads the import table so the answer comes out of the file rather than a
guess.
"""
import struct
import sys
from pathlib import Path


def sections(data, offset, count):
    out = []
    for index in range(count):
        base = offset + index * 40
        name = data[base:base + 8].rstrip(b"\0").decode("ascii", "replace")
        virtual_size, virtual_address, raw_size, raw_pointer = struct.unpack_from(
            "<IIII", data, base + 8)
        out.append((name, virtual_address, max(virtual_size, raw_size), raw_pointer))
    return out


def to_offset(rva, table):
    for _name, virtual_address, size, raw_pointer in table:
        if virtual_address <= rva < virtual_address + size:
            return raw_pointer + (rva - virtual_address)
    return None


def imports(path):
    data = Path(path).read_bytes()
    if data[:2] != b"MZ":
        raise SystemExit(f"{path} is not a PE binary")
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        raise SystemExit(f"{path} has no PE header")
    section_count, = struct.unpack_from("<H", data, pe + 6)
    optional_size, = struct.unpack_from("<H", data, pe + 20)
    magic, = struct.unpack_from("<H", data, pe + 24)
    # The data directory starts after the optional header's fixed part, which is
    # 96 bytes for PE32 and 112 for PE32+.
    directory = pe + 24 + (112 if magic == 0x20B else 96)
    table = sections(data, pe + 24 + optional_size, section_count)
    import_rva, import_size = struct.unpack_from("<II", data, directory + 8)
    if not import_rva or not import_size:
        return []
    cursor = to_offset(import_rva, table)
    if cursor is None:
        raise SystemExit(f"{path} has an import directory outside every section")
    names = []
    while True:
        descriptor = struct.unpack_from("<IIIII", data, cursor)
        if not any(descriptor):
            break
        name_offset = to_offset(descriptor[3], table)
        if name_offset is None:
            break
        end = data.index(b"\0", name_offset)
        names.append(data[name_offset:end].decode("ascii", "replace"))
        cursor += 20
    return names


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: pe_imports.py <binary>")
    binary = Path(sys.argv[1])
    beside = {entry.name.lower() for entry in binary.parent.iterdir() if entry.is_file()}
    print(f"{binary.name} imports:")
    for name in imports(binary):
        where = "beside it" if name.lower() in beside else "from the system"
        print(f"  {name:<40} {where}")


if __name__ == "__main__":
    main()
