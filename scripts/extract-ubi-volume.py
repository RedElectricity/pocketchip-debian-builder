#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Extract one UBI volume from a UBI image as a plain UBIFS image.

The SLC-mode NAND artifact carries the rootfs as volume 0 of a raw UBI
image. The Linux rescue installer expects the UBIFS payload itself, so this
helper walks the UBI eraseblocks, follows each VID header to its logical
eraseblock number, and concatenates the payloads in LEB order.

The input may be the raw UBI image or the sparse image produced by img2simg.
"""
import argparse
import struct
import sys

SPARSE_MAGIC = 0xED26FF3A
CHUNK_RAW = 0xCAC1
CHUNK_FILL = 0xCAC2
CHUNK_DONT_CARE = 0xCAC3
CHUNK_CRC32 = 0xCAC4

UBI_EC_MAGIC = b"UBI#"
UBI_VID_MAGIC = b"UBI!"
UBI_LAYOUT_VOLUME_ID = 0x7FFFFFFF


def unsparse(data: bytes) -> bytes:
    magic, _major, _minor, file_hdr_sz, chunk_hdr_sz, blk_sz, _total, chunks, _crc = struct.unpack(
        "<IHHHHIIII", data[:28]
    )
    if magic != SPARSE_MAGIC:
        raise SystemExit("input is not a sparse image")

    out = bytearray()
    pos = file_hdr_sz
    for index in range(chunks):
        chunk_type, _reserved, chunk_sz, total_sz = struct.unpack("<HHII", data[pos:pos + 12])
        body = data[pos + chunk_hdr_sz:pos + total_sz]
        size = chunk_sz * blk_sz
        if chunk_type == CHUNK_RAW:
            if len(body) != size:
                raise SystemExit(f"sparse raw chunk {index} is truncated")
            out += body
        elif chunk_type == CHUNK_FILL:
            if len(body) != 4:
                raise SystemExit(f"sparse fill chunk {index} is malformed")
            out += body * (size // 4)
        elif chunk_type == CHUNK_DONT_CARE:
            out += b"\xff" * size
        elif chunk_type == CHUNK_CRC32:
            pass
        else:
            raise SystemExit(f"unknown sparse chunk type {chunk_type:#x}")
        pos += total_sz
    return bytes(out)


def extract(image: bytes, volume_id: int, peb_size: int) -> bytes:
    if len(image) % peb_size:
        raise SystemExit(f"UBI image size {len(image)} is not a multiple of the eraseblock size {peb_size}")

    leb_size = None
    lebs: dict[int, bytes] = {}
    for peb_index in range(len(image) // peb_size):
        peb = image[peb_index * peb_size:(peb_index + 1) * peb_size]
        ec = peb[:64]
        if ec[:4] != UBI_EC_MAGIC:
            continue
        vid_off = struct.unpack(">I", ec[16:20])[0]
        data_off = struct.unpack(">I", ec[20:24])[0]
        vid = peb[vid_off:vid_off + 64]
        if vid[:4] != UBI_VID_MAGIC:
            continue
        vol_id = struct.unpack(">I", vid[8:12])[0]
        lnum = struct.unpack(">I", vid[12:16])[0]
        if vol_id != volume_id:
            continue
        if leb_size is None:
            leb_size = peb_size - data_off
        lebs[lnum] = peb[data_off:data_off + leb_size]

    if not lebs:
        raise SystemExit(f"volume {volume_id:#x} has no PEBs in this image")

    last = max(lebs)
    out = bytearray((last + 1) * leb_size)
    missing = []
    for lnum in range(last + 1):
        if lnum not in lebs:
            missing.append(lnum)
            continue
        out[lnum * leb_size:(lnum + 1) * leb_size] = lebs[lnum]

    if missing:
        raise SystemExit(f"volume {volume_id:#x} is missing LEBs: {missing[:16]}")
    if out[:4] != b"1\x18\x10\x06":
        raise SystemExit(f"volume {volume_id:#x} does not start with a UBIFS superblock")
    return bytes(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", help="raw or sparse UBI image")
    parser.add_argument("output", help="UBIFS image to write")
    parser.add_argument("--volume-id", type=lambda value: int(value, 0), default=0)
    parser.add_argument("--peb-size", type=lambda value: int(value, 0), default=2 * 1024 * 1024)
    args = parser.parse_args()

    with open(args.image, "rb") as handle:
        data = handle.read()
    if data[:4] == struct.pack("<I", SPARSE_MAGIC):
        data = unsparse(data)

    ubifs = extract(data, args.volume_id, args.peb_size)
    with open(args.output, "wb") as handle:
        handle.write(ubifs)
    print(f"extracted volume {args.volume_id:#x}: {len(ubifs)} bytes -> {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
