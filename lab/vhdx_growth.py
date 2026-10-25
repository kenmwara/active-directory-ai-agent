"""Read-only: exact space a Hyper-V merge needs. A merge writes the child's data into its parent, so the parent grows by
the parent-sized blocks the child touches that the parent has not allocated yet. Parses each VHDX's region table,
metadata (block size, sector size, virtual size) and BAT (block states) per the VHDX spec. Opens files read-only.
Usage: python vhdx_growth.py <dir>   (prints each file's allocation and the growth of merging every child into its parent)"""
import struct
import sys
import uuid
from pathlib import Path

BAT = uuid.UUID("2DC27766-F623-4200-9D64-115E9BFD4A08")
META = uuid.UUID("8B7CA206-4790-4B9A-B8FE-575F050F886E")
FILE_PARAMS = uuid.UUID("CAA16737-FA36-4D43-B3B6-33F0AA44E76B")
VDISK_SIZE = uuid.UUID("2FA54224-CD1B-4876-B211-5DBED83BF4B8")
LSECTOR = uuid.UUID("8141BF1D-A96F-4709-BA47-F233A8FAAB5F")
PARENT_LOC = uuid.UUID("A8D35F2D-B30B-454D-ABF7-D3D84834AB0C")
ALLOCATED = {6, 7}  # PAYLOAD_BLOCK_FULLY_PRESENT, PAYLOAD_BLOCK_PARTIALLY_PRESENT (differencing)


def parse(path: Path) -> dict:
    with open(path, "rb") as f:
        f.seek(192 * 1024)  # region table 1
        rt = f.read(64 * 1024)
        assert rt[:4] == b"regi", f"{path.name}: no region table"
        count = struct.unpack_from("<I", rt, 8)[0]
        regions = {}
        for i in range(count):
            g, off, length, _req = struct.unpack_from("<16sQII", rt, 16 + i * 32)
            regions[uuid.UUID(bytes_le=g)] = (off, length)
        moff, mlen = regions[META]
        f.seek(moff)
        md = f.read(mlen)
        assert md[:8] == b"metadata"
        n = struct.unpack_from("<H", md, 10)[0]
        items = {}
        for i in range(n):
            g, ioff, ilen, _flags = struct.unpack_from("<16sIII", md, 32 + i * 32)
            items[uuid.UUID(bytes_le=g)] = md[ioff:ioff + ilen]
        block_size, fp_flags = struct.unpack_from("<II", items[FILE_PARAMS])
        vsize = struct.unpack_from("<Q", items[VDISK_SIZE])[0]
        lsec = struct.unpack_from("<I", items[LSECTOR])[0]
        has_parent = bool(fp_flags & 2)
        chunk = (2 ** 23 * lsec) // block_size
        nblocks = -(-vsize // block_size)
        boff, blen = regions[BAT]
        f.seek(boff)
        bat = f.read(blen)
    entries = struct.unpack_from(f"<{blen // 8}Q", bat)
    alloc = set()
    k = 0
    for i, e in enumerate(entries):
        if (i + 1) % (chunk + 1) == 0:  # sector-bitmap entry after every `chunk` payload entries
            continue
        if k >= nblocks:
            break
        if (e & 7) in ALLOCATED:
            alloc.add(k)
        k += 1
    return {"block": block_size, "vsize": vsize, "alloc": alloc, "parent": has_parent}


def growth(child: dict, parent: dict) -> int:
    pb, cb = parent["block"], child["block"]
    touched = set()
    for b in child["alloc"]:
        start, end = b * cb, (b + 1) * cb - 1
        touched.update(range(start // pb, end // pb + 1))
    return len(touched - parent["alloc"]) * pb


if __name__ == "__main__":
    root = Path(sys.argv[1])
    files = {p.name: p for p in root.rglob("*") if p.suffix.lower() in (".vhdx", ".avhdx")}
    info = {name: parse(p) for name, p in sorted(files.items())}
    for name, d in info.items():
        print(f"{name:55} block {d['block'] // 2**20:>3} MB  allocated {len(d['alloc']) * d['block'] / 2**30:6.2f} GB  file {files[name].stat().st_size / 2**30:6.2f} GB")
    pairs = sys.argv[2:]  # child=parent pairs
    for pair in pairs:
        c, p = pair.split("=")
        print(f"merge {c} -> {p}: parent grows by {growth(info[c], info[p]) / 2**30:.2f} GB")
