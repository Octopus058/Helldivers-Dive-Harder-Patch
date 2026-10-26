"""Compile the Dive Harder hooks into character_state_machine and emit standalone boot packages.

Usage (from the project root):
    python tools/build.py                      # locate the game automatically
    python tools/build.py --contents "E:\\Steam\\steamapps\\common\\Helldivers\\contents"
    python tools/build.py --luajit "C:\\path\\to\\luajit.exe"

Output:
    build/cs_dh.lua / build/cs_dh.bc
    dist/dive_harder_vanilla.bin   (vanilla base package)
    dist/dive_harder_qol.bin       (QoL base package, only when a QoL backup is found)

How it works: the game only reads the single boot package named by `boot_package` in
settings.ini. We swap the one Lua resource `character_state_machine` for a hooked build
and leave every other resource byte-for-byte untouched, then name the package after the
hash of its target path (05cd02202827e9a0 = murmur64a("resource_packages/boot_dh")).
"""
import argparse
import glob
import os
import shutil
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from bundle import (  # noqa: E402
    find_resource,
    murmur64a,
    read_bundle,
    replace_resource,
    sha256_file,
    write_bundle,
)

TARGET_PATH = "lua/character_states/character_state_machine"
TARGET_HASH = murmur64a(TARGET_PATH.encode())
BOOT_HASH = murmur64a(b"resource_packages/boot")
BOOT_DH_PATH = "resource_packages/boot_dh"
BOOT_DH_HASH = murmur64a(BOOT_DH_PATH.encode())

DEFAULT_CONTENTS = r"E:\Steam\steamapps\common\Helldivers\contents"
KNOWN_LUAJIT = r"D:\Desktop\luajit-decompiler-v2\luajit.exe"

# 9e13b2414b41b842 = murmur64a("resource_packages/boot")
BOOT_FILE = f"{BOOT_HASH:016x}"
QOL_BOOT_SHA = "06EAF26FFFF1806F675AB804E865FB2B516DFE00A6F2C8B1AB40360D28ACF957"


def log(message=""):
    print(message, flush=True)


def find_contents(explicit):
    candidates = [explicit, os.environ.get("HD_CONTENTS"), DEFAULT_CONTENTS]

    for path in candidates:
        if path and os.path.isfile(os.path.join(path, "settings.ini")):
            return os.path.abspath(path)

    raise SystemExit(
        "Helldivers contents directory not found.\n"
        "Pass it explicitly, for example:\n"
        '  python tools/build.py --contents "E:\\Steam\\steamapps\\common\\Helldivers\\contents"\n'
        "or set the HD_CONTENTS environment variable."
    )


def find_luajit(explicit):
    candidates = [explicit, os.environ.get("LUAJIT"), KNOWN_LUAJIT, shutil.which("luajit")]

    for path in candidates:
        if path and os.path.isfile(path):
            return path

    raise SystemExit(
        "LuaJIT not found. LuaJIT 2.0.3 is required (the Lua runtime of this game):\n"
        "  --luajit C:\\path\\to\\luajit.exe or set the LUAJIT environment variable"
    )


def compile_lua(luajit, src, dst):
    result = subprocess.run([luajit, "-b", "-s", src, dst], capture_output=True, text=True)

    if result.returncode != 0:
        raise SystemExit(f"LuaJIT compilation failed:\n{result.stdout}\n{result.stderr}")

    return open(dst, "rb").read()


def resource_bytecode(bundle_path):
    """Return the original character_state_machine bytecode (the first 8 bytes are size and version)."""
    raw, _header = read_bundle(bundle_path)
    res = find_resource(raw, TARGET_HASH)
    data = raw[res["data_start"]:res["data_end"]]

    if len(data) < 8:
        raise SystemExit(f"{bundle_path}: character_state_machine resource is too small to be Lua")

    return data[8:]


def pick_bases(contents, qol_base_override):
    boot = os.path.join(contents, BOOT_FILE)
    vanilla = os.path.join(contents, BOOT_FILE + ".orig")

    if not os.path.isfile(vanilla):
        raise SystemExit(
            f"missing vanilla backup: {BOOT_FILE}.orig\n"
            "The QoL installer or this mod's install package usually leaves that file behind.\n"
            f"On a clean game with no QoL, just copy {BOOT_FILE} to {BOOT_FILE}.orig."
        )

    qol = None

    if qol_base_override:
        if not os.path.isfile(qol_base_override):
            raise SystemExit(f"--qol-base file does not exist: {qol_base_override}")
        qol = qol_base_override
    else:
        # The QoL installer leaves .orig plus a backup; prefer a dedicated QoL base backup,
        # otherwise fall back to the current boot package if its hash says it is QoL.
        patterns = [
            BOOT_FILE + ".qol_boot_backup_*",
            BOOT_FILE + ".enemy_stats_backup_*",
        ]
        backups = []

        for pattern in patterns:
            backups += glob.glob(os.path.join(contents, pattern))

        backups.sort()

        if backups:
            qol = backups[-1]
        elif os.path.isfile(boot) and sha256_file(boot) == QOL_BOOT_SHA:
            qol = boot

    return vanilla, qol


def patch_bundle(base_path, new_data, out_path):
    raw, header = read_bundle(base_path)
    res = find_resource(raw, TARGET_HASH)
    patched_raw = replace_resource(raw, res, new_data)
    write_bundle(out_path, patched_raw, header)

    check_raw, _ = read_bundle(out_path)
    delta = len(new_data) - res["size"]

    # The size field is meant to change, so only compare the prefix up to size_field.
    assert check_raw[:res["size_field"]] == raw[:res["size_field"]], "resource table was damaged"
    assert struct.unpack_from("<I", check_raw, res["size_field"])[0] == len(new_data), "size field is wrong"
    assert check_raw[res["data_start"]:res["data_start"] + len(new_data)] == new_data, "target resource mismatch"
    assert check_raw[res["data_start"] + len(new_data):] == raw[res["data_end"]:], "bytes after the resource changed"

    log(f"  resource #{res['index']}: {res['size']} -> {len(new_data)} bytes, every other resource byte-identical ({delta:+d})")
    return sha256_file(out_path)


def main():
    parser = argparse.ArgumentParser(description="Build the Dive Harder boot packages")
    parser.add_argument("--contents", help="Helldivers contents directory")
    parser.add_argument("--luajit", help="LuaJIT 2.0.3 executable")
    parser.add_argument("--qol-base", help="explicit QoL base package (default: auto-detect .qol_boot_backup_*)")
    parser.add_argument("--out", default=os.path.join(ROOT, "dist"), help="output directory")
    parser.add_argument("--skip-verify", action="store_true", help="skip the base bytecode check (not recommended)")
    parser.add_argument("--extra", action="append", default=[],
                        help="append an extra Lua module to the build (may be repeated)")
    parser.add_argument("--skip-ping", action="store_true",
                        help="diagnostics: do not compile ping_hud.lua (no HUD ping / PING WINDOW / friends refresh)")
    args = parser.parse_args()

    contents = find_contents(args.contents)
    luajit = find_luajit(args.luajit)
    log(f"contents: {contents}")
    log(f"luajit:   {luajit}")

    base_src = os.path.join(ROOT, "vendor", "base_csm.lua")
    hook_src = os.path.join(ROOT, "lua", "dive_harder.lua")

    if not os.path.isfile(base_src):
        raise SystemExit(
            f"missing base file: {base_src}\n"
            "It is the decompiled lua/character_states/character_state_machine, used for building only\n"
            "and never shipped in a release package. See the build section of the README."
        )

    vanilla, qol = pick_bases(contents, args.qol_base)
    log(f"vanilla base: {os.path.basename(vanilla)}")
    log(f"qol base:     {os.path.basename(qol) if qol else '(none, skipping the QoL package)'}")

    build_dir = os.path.join(ROOT, "build")
    os.makedirs(build_dir, exist_ok=True)
    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)

    # 1) Base check: the decompiled text must recompile to exactly the game's bytecode.
    if not args.skip_verify:
        base_check = os.path.join(build_dir, "base_check.bc")
        compile_lua(luajit, base_src, base_check)

        if open(base_check, "rb").read() != resource_bytecode(vanilla):
            raise SystemExit(
                "base check failed: recompiling vendor/base_csm.lua does not reproduce the game's bytecode.\n"
                "This base is not the decompilation of the current game version; regenerate it (see the README)."
            )

        log("base check: recompiled bytecode matches the original byte-for-byte")

    # 2) Assemble and compile
    base_text = open(base_src, encoding="utf-8").read().lstrip("\ufeff")
    hook_text = open(hook_src, encoding="utf-8").read().lstrip("\ufeff")

    if not base_text.endswith("\n"):
        base_text += "\n"

    parts = [base_text, "\n", hook_text]

    # ping / HUD / friends refresh (local quality-of-life only)
    extra_modules = []

    if not args.skip_ping:
        extra_modules.append(os.path.join(ROOT, "lua", "ping_hud.lua"))

    for extra in args.extra:
        extra_modules.append(extra if os.path.isabs(extra) else os.path.join(ROOT, extra))

    for module_path in extra_modules:
        if not os.path.isfile(module_path):
            raise SystemExit(f"missing {module_path}")

        module_text = open(module_path, encoding="utf-8").read().lstrip("\ufeff")

        if not module_text.endswith("\n"):
            module_text += "\n"

        parts.append("\n")
        parts.append(module_text)

    combined = os.path.join(build_dir, "cs_dh.lua")
    open(combined, "w", encoding="utf-8", newline="\n").write("".join(parts))

    bc_path = os.path.join(build_dir, "cs_dh.bc")
    patched_bc = compile_lua(luajit, combined, bc_path)
    log(f"new bytecode: {len(patched_bc)} bytes -> {os.path.relpath(bc_path, ROOT)}")

    new_data = struct.pack("<II", len(patched_bc), 2) + patched_bc

    # 3) Emit the boot packages
    log("\n=== vanilla ===")
    log(f"  sha256={patch_bundle(vanilla, new_data, os.path.join(out_dir, 'dive_harder_vanilla.bin'))}")

    if qol:
        log("\n=== qol ===")
        log(f"  sha256={patch_bundle(qol, new_data, os.path.join(out_dir, 'dive_harder_qol.bin'))}")

    log("")
    log(f"boot package path {BOOT_DH_PATH}")
    log(f"boot package file {BOOT_DH_HASH:016x}")


if __name__ == "__main__":
    sys.exit(main())
