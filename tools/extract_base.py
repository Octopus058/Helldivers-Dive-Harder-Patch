r"""Extract the original character_state_machine bytecode from a game boot package.

The bytecode is what vendor/base_csm.lua is decompiled from.

Usage:
    python tools/extract_base.py                      # auto-detect contents / 9e13...orig
    python tools/extract_base.py --bundle <path>      # explicit boot package

Writes build/cs_orig.bc, which then has to be decompiled once by hand (the decompiler
is not part of this repository):

    luajit-decompiler-v2.exe build\cs_orig.bc
    # the decompiler writes its output into its own output\ directory (same name, .lua)
    # save that file as vendor/base_csm.lua

tools/build.py then checks that recompiling vendor/base_csm.lua reproduces
build/cs_orig.bc byte for byte, and refuses to build when it does not (base and game
version do not match).
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from bundle import find_resource, murmur64a, read_bundle  # noqa: E402

TARGET_PATH = "lua/character_states/character_state_machine"
TARGET_HASH = murmur64a(TARGET_PATH.encode())
BOOT_FILE = f"{murmur64a(b'resource_packages/boot'):016x}"
DEFAULT_CONTENTS = r"E:\Steam\steamapps\common\Helldivers\contents"


def main():
    parser = argparse.ArgumentParser(description="Extract the original character_state_machine bytecode")
    parser.add_argument("--bundle", help="boot package path (default: contents\\9e13....orig)")
    parser.add_argument("--contents", default=os.environ.get("HD_CONTENTS", DEFAULT_CONTENTS))
    args = parser.parse_args()

    bundle = args.bundle or os.path.join(args.contents, BOOT_FILE + ".orig")

    if not os.path.isfile(bundle):
        raise SystemExit(
            f"boot package not found: {bundle}\n"
            f"Pass --bundle, or install QoL / restore a {BOOT_FILE}.orig first."
        )

    raw, _header = read_bundle(bundle)
    res = find_resource(raw, TARGET_HASH)
    data = raw[res["data_start"]:res["data_end"]]
    code = data[8:]

    build_dir = os.path.join(ROOT, "build")
    os.makedirs(build_dir, exist_ok=True)
    out = os.path.join(build_dir, "cs_orig.bc")
    open(out, "wb").write(code)

    print(f"resource: {TARGET_PATH} (0x{TARGET_HASH:016x}) #{res['index']}, {len(data)} bytes")
    print(f"bytecode: {out} ({len(code)} bytes)")
    print("")
    print("next steps:")
    print(f"  luajit-decompiler-v2.exe {os.path.relpath(out, ROOT)}")
    print("  save the decompiled source as vendor/base_csm.lua")
    print("  python tools/build.py   # verifies that the recompiled base matches the original")
