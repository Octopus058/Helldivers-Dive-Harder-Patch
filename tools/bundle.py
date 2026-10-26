"""Read/write Helldivers resource bundles and compute murmur64a.

Bundle layout:
    u32 magic(0xF0000004) | u32 decompressed_size | u32 0
    then blocks: u32 zlib block length + zlib payload (each block decompresses to 64 KiB)
Decompressed payload:
    u32 resource_count | 256-byte constant header | (u64 type, u64 name) resource table
    then per resource: u32 variant_count, u32 zero, (u32 index, u32 size, u32 extra) * variants, data
"""
import hashlib
import struct
import zlib

MASK = (1 << 64) - 1
M = 0xC6A4A7935BD1E995
R = 47

LUA_TYPE = 0xA14E8DFA2CD117E2
BLOCK = 65536


def murmur64a(data: bytes, seed: int = 0) -> int:
    """MurmurHash64A, which the game uses to turn a resource path into a file name / resource name."""
    length = len(data)
    h = (seed ^ (length * M)) & MASK
    nblocks = length // 8

    for i in range(nblocks):
        k = struct.unpack_from("<Q", data, i * 8)[0]
        k = (k * M) & MASK
        k ^= k >> R
        k = (k * M) & MASK
        h ^= k
        h = (h * M) & MASK

    tail = data[nblocks * 8:]

    if tail:
        h ^= int.from_bytes(tail, "little")
        h = (h * M) & MASK

    h ^= h >> R
    h = (h * M) & MASK
    h ^= h >> R
    return h


def package_hash(path: str) -> str:
    """Boot package file name = murmur64a("resource_packages/xxx"), handy for installer cross-checks."""
    return f"{murmur64a(path.encode()):016x}"


def sha256_file(path: str) -> str:
    return hashlib.sha256(open(path, "rb").read()).hexdigest().upper()


def read_bundle(path: str) -> tuple[bytes, bytes]:
    """Return (decompressed payload, 16-byte header). Truncated to the size stored in the header."""
    data = open(path, "rb").read()
    out = bytearray()
    pos = 16
    block_size = struct.unpack_from("<I", data, 12)[0]

    while pos < len(data):
        if pos != 16:
            block_size = struct.unpack_from("<I", data, pos)[0]
            pos += 4

        if block_size <= 0 or pos + block_size > len(data):
            raise ValueError(f"{path}: corrupt zlib block at {pos}")

        out += zlib.decompress(data[pos:pos + block_size])
        pos += block_size

    size = struct.unpack_from("<I", data, 4)[0]
    return bytes(out[:size]), data[:16]


def write_bundle(path: str, raw: bytes, header: bytes) -> None:
    """Recompress with the original header (keeping magic and friends, only the size changes)."""
    out_header = bytearray(header[:12])
    struct.pack_into("<I", out_header, 4, len(raw))

    out = bytearray(out_header)
    padded = raw + b"\0" * ((-len(raw)) % BLOCK)

    for offset in range(0, len(padded), BLOCK):
        block = zlib.compress(padded[offset:offset + BLOCK], 9)
        out += struct.pack("<I", len(block)) + block

    with open(path, "wb") as handle:
        handle.write(out)


def find_resource(raw: bytes, name_hash: int, rtype: int = LUA_TYPE) -> dict:
    """Locate one resource in the decompressed payload and return its data range and size field."""
    count = struct.unpack_from("<I", raw, 0)[0]
    pos = 4 + 256 + count * 16

    for index in range(count):
        res_type, res_name = struct.unpack_from("<QQ", raw, pos)
        pos += 16

        variant_count, _zero = struct.unpack_from("<II", raw, pos)
        pos += 8

        variants_pos = pos
        variants = []

        for _ in range(variant_count):
            variants.append(struct.unpack_from("<III", raw, pos))
            pos += 12

        size = variants[0][1] if variants else 0

        if res_name == name_hash and res_type == rtype:
            return {
                "index": index,
                "data_start": pos,
                "data_end": pos + size,
                "size_field": variants_pos + 4,
                "size": size,
                "variants": variants,
            }

        pos += size

    raise KeyError(f"resource 0x{name_hash:016x} not found")


def replace_resource(raw: bytes, res: dict, new_data: bytes) -> bytes:
    """Replace the resource payload and keep the variant size field in sync."""
    out = bytearray(raw[:res["data_start"]] + new_data + raw[res["data_end"]:])
    struct.pack_into("<I", out, res["size_field"], len(new_data))
    return bytes(out)
