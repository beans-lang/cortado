#!/usr/bin/env python3
"""Fetch a pinned Skia SDK. Never modifies manifests or native builds."""
import argparse
import hashlib
import json
import platform
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", help="macos|linux|windows followed by -arm64 or -x64")
    parser.add_argument("--archive", type=Path, help="use an already downloaded archive")
    parser.add_argument("--fetch-only", action="store_true", help="fetch a cross-target SDK without building")
    parser.add_argument("--sanitize", action="store_true", help="build an ASan/UBSan graphics bridge separately")
    args = parser.parse_args()
    system = {"Darwin": "macos", "Linux": "linux", "Windows": "windows"}.get(platform.system())
    machine = {"aarch64": "arm64", "arm64": "arm64", "AMD64": "x64", "x86_64": "x64"}.get(platform.machine())
    target = args.target or f"{system}-{machine}"
    lock = json.loads((ROOT / "skia/dependencies.json").read_text())
    if target not in lock["assets"]:
        parser.error(f"unsupported Skia target: {target}")
    asset = lock["assets"][target]
    destination = ROOT / "build/skia" / target
    stamp = destination / ".cortado-sdk.json"
    if stamp.is_file() and json.loads(stamp.read_text()) == asset:
        print(f"Skia {lock['release']} ready: {destination}")
        if not args.fetch_only:
            build_engine(destination, target, system, machine, args.sanitize)
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".skia-", dir=destination.parent) as scratch:
        scratch = Path(scratch)
        archive = args.archive or scratch / "sdk.zip"
        if not args.archive:
            print(f"Downloading pinned Skia SDK for {target}", flush=True)
            urllib.request.urlretrieve(asset["url"], archive)
        with archive.open("rb") as source:
            digest = hashlib.file_digest(source, "sha256").hexdigest()
        if digest != asset["sha256"]:
            raise SystemExit("Skia checksum mismatch; no files installed")
        unpacked = scratch / "sdk"
        with zipfile.ZipFile(archive) as bundle:
            for entry in bundle.infolist():
                path = (unpacked / entry.filename).resolve()
                if not path.is_relative_to(unpacked.resolve()):
                    raise SystemExit("unsafe path in Skia archive")
            bundle.extractall(unpacked)
        (unpacked / ".cortado-sdk.json").write_text(json.dumps(asset, indent=2) + "\n")
        # Only replace this tool's generated SDK directory.
        if destination.exists():
            shutil.rmtree(destination)
        unpacked.rename(destination)
    print(f"Skia {lock['release']} ready: {destination}")
    if not args.fetch_only:
        build_engine(destination, target, system, machine, args.sanitize)


def build_engine(sdk, target, system, machine, sanitize=False):
    if target != f"{system}-{machine}":
        raise SystemExit("Cross-target SDK fetched; build on that target or pass --fetch-only")
    libraries = list((sdk / "out").glob("Release-*"))
    if len(libraries) != 1:
        raise SystemExit("Pinned SDK has an unexpected library layout")
    suffix = "-sanitized" if sanitize else ""
    build = ROOT / "build/skia" / f"engine-{target}{suffix}"
    output = ROOT / f"build/skia/lib{suffix}"
    subprocess.run(["cmake", "-S", str(ROOT / "skia"), "-B", str(build),
                    f"-DSKIA_SDK={sdk}", f"-DSKIA_LIB={libraries[0]}",
                    f"-DCORTADO_SANITIZE={'ON' if sanitize else 'OFF'}",
                    "-DCMAKE_BUILD_TYPE=Release", f"-DCMAKE_LIBRARY_OUTPUT_DIRECTORY={output}",
                    f"-DCMAKE_RUNTIME_OUTPUT_DIRECTORY={output}",
                    f"-DCMAKE_RUNTIME_OUTPUT_DIRECTORY_RELEASE={output}",
                    f"-DCMAKE_LIBRARY_OUTPUT_DIRECTORY_RELEASE={output}"], check=True)
    subprocess.run(["cmake", "--build", str(build), "--config", "Release", "--parallel", "4"], check=True)


if __name__ == "__main__":
    main()
