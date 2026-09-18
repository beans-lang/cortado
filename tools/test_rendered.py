#!/usr/bin/env python3
"""Opt-in shared-renderer gate. Does not change the native desktop default."""
import argparse
import difflib
import os
import platform
from pathlib import Path
import shutil
import shlex
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(arguments, *, env, capture=False):
    print("+ " + " ".join(map(str, arguments)), flush=True)
    return subprocess.run(list(map(str, arguments)), cwd=ROOT, env=env, check=True,
                          text=True, stdout=subprocess.PIPE if capture else None).stdout


def same(expected, actual, label):
    if expected != actual:
        sys.stderr.writelines(difflib.unified_diff(expected.splitlines(True), actual.splitlines(True),
                                                  fromfile=label, tofile="regenerated"))
        raise SystemExit(f"Generated file drift: {label}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sanitize", action="store_true", help="also run native Beans with ASan/UBSan")
    parser.add_argument("--skip-interpreter", action="store_true", help="explicitly omit the interpreter leg")
    args = parser.parse_args()
    env = os.environ.copy()
    compiler = Path(env.get("BEANSC", ROOT / "../../beans/build/beansc")).resolve()
    if not compiler.is_file():
        located = shutil.which("beansc")
        if not located:
            raise SystemExit("Set BEANSC or put beansc on PATH")
        compiler = Path(located)
    tree = compiler.parent.parent
    for variable, relative in {"BEANS_RUNTIME": "runtime/beans_rt.c", "BEANS_STDLIB": "stdlib/std",
                               "BEANS_ENCODING": "runtime/encoding", "BEANS_NET": "runtime/net",
                               "BEANS_LOG": "runtime/log"}.items():
        if (tree / relative).exists():
            env[variable] = str(tree / relative)
    run([sys.executable, "tools/prepare_skia.py"], env=env)
    if args.sanitize:
        run([sys.executable, "tools/prepare_skia.py", "--sanitize"], env=env)
    generator = ROOT / "build/cortado-bx-render-gate"
    run([compiler, "build", "examples/cortado_bx.b", "-o", generator], env=env)
    with tempfile.TemporaryDirectory(prefix="cortado-render-") as scratch:
        scratch = Path(scratch)
        generated = scratch / "ffi.b"
        run([compiler, "bindgen", "skia/bridge.h", "-o", generated, "--package", "cortado_skia", "--pub"], env=env)
        same((ROOT / "skia/ffi.b").read_text(), generated.read_text(), "skia/ffi.b")
        for base, output in [(ROOT / "templates", ROOT / "generated/templates"),
                             (ROOT / "examples/rendered/site", ROOT / "examples/rendered/generated/site"),
                             (ROOT / "examples/showcase/site", ROOT / "examples/showcase/generated/site")]:
            expected_names = {source.with_suffix(".b").name for source in base.glob("*.bx")}
            actual_names = {generated.name for generated in output.glob("*.b")}
            if expected_names != actual_names:
                raise SystemExit(f"Generated file set drift in {output.relative_to(ROOT)}: "
                                 f"missing={sorted(expected_names - actual_names)}, "
                                 f"orphaned={sorted(actual_names - expected_names)}")
            for source in sorted(base.glob("*.bx")):
                generated = scratch / source.with_suffix(".b").name
                run([generator, "build", source, "-o", generated], env=env)
                same((output / generated.name).read_text(), generated.read_text(), str(source.relative_to(ROOT)))
        for diagnostic in sorted((ROOT / "examples/rendered/tests").rglob("check_diagnostics.py")):
            run([sys.executable, diagnostic], env=dict(env, CORTADO_BX=str(generator)))
        tests = sorted(str(source.relative_to(ROOT))
                       for directory in [ROOT / "skia/tests", ROOT / "examples/rendered/tests"]
                       for source in directory.rglob("main.b"))
        for index, source in enumerate(tests):
            executable = scratch / f"test-{index}"
            if not args.skip_interpreter:
                run([compiler, "run", source], env=env)
            run([compiler, "build", source, "-o", executable], env=env)
            run([executable], env=env)
            if args.sanitize:
                library = {"Darwin": "libcortado_skia_engine.dylib", "Linux": "libcortado_skia_engine.so",
                           "Windows": "cortado_skia_engine.dll"}[platform.system()]
                sanitized = dict(env, BEANS_SANITIZE="address,undefined",
                                 CORTADO_SKIA_LIBRARY=str(ROOT / "build/skia/lib-sanitized" / library))
                run([compiler, "build", source, "-o", str(executable) + "-asan"], env=sanitized)
                run([str(executable) + "-asan"], env=sanitized)
        executable = scratch / "window"
        run([compiler, "build", "examples/rendered/main.b", "-o", executable], env=env)
        run([executable, "--window-smoke"], env=env)
        # The showcase is the demo people run first; a demo nothing builds rots.
        showcase = scratch / "showcase"
        run([compiler, "build", "examples/showcase/main.b", "-o", showcase], env=env)
        run([showcase, "--smoke"], env=env)
        if platform.system() == "Darwin":
            rows = [shlex.split(line, comments=True) for line in (ROOT / "beans.pot").read_text().splitlines()]
            sources = [row[2] for row in rows if row[:2] == ["csrc", "macos"]]
            frameworks = [part for row in rows if row[:3] == ["link", "macos", "framework"]
                          for part in ["-framework", row[3]]]
            flags = ["clang", "-fno-objc-arc", "-Wno-deprecated-declarations"]
            service = scratch / "native-services"
            run([*flags, *sources, "tests/mac_shared_services.m", *frameworks, "-o", service], env=env)
            run([service], env=env)
            if args.sanitize:
                sanitized_service = scratch / "native-services-asan"
                run([*flags, "-fsanitize=address,undefined", "-fno-omit-frame-pointer", *sources,
                     "tests/mac_shared_services.m", *frameworks, "-o", sanitized_service], env=env)
                run([sanitized_service], env=env)
    if args.skip_interpreter:
        print("SKIP interpreter: explicitly requested")
    print("ok shared renderer: markup drift, Skia pixels, editing, ownership, .bx scene, desktop surface, showcase")


if __name__ == "__main__":
    main()
