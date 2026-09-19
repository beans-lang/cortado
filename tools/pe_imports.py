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


def thunk_names(data, table, rva, magic):
    """The function names one descriptor imports, in order."""
    out = []
    offset = to_offset(rva, table)
    if offset is None:
        return out
    step = 8 if magic == 0x20B else 4
    mask = 1 << (63 if magic == 0x20B else 31)
    while True:
        entry = int.from_bytes(data[offset:offset + step], "little")
        if not entry:
            break
        if entry & mask:
            out.append(f"#{entry & 0xFFFF}")
        else:
            name_offset = to_offset(entry & 0x7FFFFFFF, table)
            if name_offset is None:
                break
            end = data.index(b"\0", name_offset + 2)
            out.append(data[name_offset + 2:end].decode("ascii", "replace"))
        offset += step
    return out


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
        library = data[name_offset:end].decode("ascii", "replace")
        # The lookup table survives binding; the address table may not.
        lookup = descriptor[0] or descriptor[4]
        names.append((library, thunk_names(data, table, lookup, magic)))
        cursor += 20
    return names


def exports(path):
    """Every name a PE binary exports."""
    data = Path(path).read_bytes()
    if data[:2] != b"MZ":
        return None
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        return None
    section_count, = struct.unpack_from("<H", data, pe + 6)
    optional_size, = struct.unpack_from("<H", data, pe + 20)
    magic, = struct.unpack_from("<H", data, pe + 24)
    directory = pe + 24 + (112 if magic == 0x20B else 96)
    table = sections(data, pe + 24 + optional_size, section_count)
    export_rva, export_size = struct.unpack_from("<II", data, directory)
    if not export_rva or not export_size:
        return set()
    base = to_offset(export_rva, table)
    if base is None:
        return set()
    count, names_rva = struct.unpack_from("<I", data, base + 24)[0], \
        struct.unpack_from("<I", data, base + 32)[0]
    pointers = to_offset(names_rva, table)
    if pointers is None:
        return set()
    found = set()
    for index in range(count):
        rva, = struct.unpack_from("<I", data, pointers + index * 4)
        offset = to_offset(rva, table)
        if offset is None:
            continue
        end = data.index(b"\0", offset)
        found.add(data[offset:end].decode("ascii", "replace"))
    return found


def resolve(library, beside_dir):
    """Where Windows would find this DLL. An API set has no file of its own;
    the CRT ones are ucrtbase, which is what the loader redirects them to."""
    system = Path(r"C:\Windows\System32")
    for candidate in (beside_dir / library, system / library):
        if candidate.is_file():
            return candidate
    if library.lower().startswith("api-ms-win-crt-"):
        ucrt = system / "ucrtbase.dll"
        if ucrt.is_file():
            return ucrt
    return None


def verify(binary):
    """Report every import the machine cannot satisfy. This is what an
    ENTRYPOINT_NOT_FOUND means, named rather than inferred."""
    missing = 0
    for library, functions in imports(binary):
        target = resolve(library, binary.parent)
        if target is None:
            print(f"  {library}: no such DLL on this machine")
            missing += 1
            continue
        available = exports(target)
        if available is None:
            print(f"  {library}: {target} is not readable as PE")
            continue
        absent = [name for name in functions if name not in available and not name.startswith("#")]
        if absent:
            missing += len(absent)
            print(f"  {library} ({target.name}) does not export:")
            for name in absent:
                print(f"      {name}")
    if missing:
        print(f"{missing} import(s) cannot be resolved")
    else:
        print("every import resolves on this machine")
    return missing


def main():
    if len(sys.argv) not in (2, 3):
        raise SystemExit("usage: pe_imports.py [--verify] <binary>")
    check = "--verify" in sys.argv[1:]
    binary = Path([a for a in sys.argv[1:] if a != "--verify"][0])
    if check:
        raise SystemExit(1 if verify(binary) else 0)
    beside = {entry.name.lower() for entry in binary.parent.iterdir() if entry.is_file()}
    print(f"{binary.name} imports:")
    for name, functions in imports(binary):
        where = "beside it" if name.lower() in beside else "from the system"
        print(f"  {name:<40} {where} ({len(functions)})")
        for function in functions:
            print(f"      {function}")


if __name__ == "__main__":
    main()
