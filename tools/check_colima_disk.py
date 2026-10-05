"""Check or repair partition 1 of an OFFLINE Colima raw disk on macOS.

The repair requires a preserved, equally sized backup image. Never use while
the VM runs. The tool refuses disks open by another process, logs fsck
diagnostics, verifies a clean second check, and writes only
changed chunks into the original image. A sparse partition file is retained.
"""
import argparse
import os
from pathlib import Path
import struct
import subprocess


def check(disk, log, backup=None):
    disk = disk.resolve(strict=True)
    if backup:
        backup = backup.resolve(strict=True)
        if backup == disk or backup.stat().st_size != disk.stat().st_size:
            raise RuntimeError("A separate full-size backup is required")
    opened = subprocess.run(["lsof", "-t", "--", str(disk)], capture_output=True)
    if opened.returncode != 1 or opened.stdout:
        raise RuntimeError("Disk is in use or its offline state cannot be verified")
    log.parent.mkdir(parents=True, exist_ok=True)
    partition = log.with_suffix(log.suffix + ".partition.raw")
    if log.exists() or partition.exists():
        raise RuntimeError("Choose a fresh log path; recovery files are preserved")
    # macOS raw-device fsync can return EINVAL. Check a sparse partition file
    # instead, then copy only changed blocks back into the offline image.
    with disk.open("rb") as source:
        source.seek(512)
        header = source.read(512)
        if header[:8] != b"EFI PART":
            raise RuntimeError("Disk has no GPT header")
        entry_sector, _, entry_size = struct.unpack_from("<QII", header, 72)
        source.seek(entry_sector * 512)
        entry = source.read(entry_size)
        first, last = struct.unpack_from("<QQ", entry, 32)
        offset, size = first * 512, (last - first + 1) * 512
        if first == 0 or size <= 0 or offset + size > disk.stat().st_size:
            raise RuntimeError("Invalid partition bounds")
        source.seek(offset)
        with partition.open("xb") as target:
            os.chmod(partition, 0o600)
            remaining = size
            while remaining:
                block = source.read(min(remaining, 4 << 20))
                if not block:
                    raise RuntimeError("Truncated source image")
                if block.count(b"\0") == len(block):
                    target.seek(len(block), 1)
                else:
                    target.write(block)
                remaining -= len(block)
            target.truncate(size)
            target.flush()
            os.fsync(target.fileno())
    fsck = "/opt/homebrew/opt/e2fsprogs/sbin/e2fsck"
    with log.open("xb") as stream:
        os.chmod(log, 0o600)
        run = subprocess.run([fsck, "-fy" if backup else "-fn", str(partition)], stdout=stream, stderr=stream)
    print(f"fsck exit: {run.returncode}; log: {log}")
    if backup:
        if run.returncode not in (0, 1, 2):
            raise RuntimeError("Filesystem repair did not complete")
        verify = log.with_suffix(log.suffix + ".verify")
        with verify.open("xb") as stream:
            run = subprocess.run([fsck, "-fn", str(partition)], stdout=stream, stderr=stream)
        if run.returncode != 0:
            raise RuntimeError("Filesystem still has errors; backup retained")
        print("Independent read-only fsck: CLEAN")
        with partition.open("rb") as repaired, disk.open("r+b") as target:
            target.seek(offset)
            remaining = size
            changed = 0
            while remaining:
                block = repaired.read(min(remaining, 4 << 20))
                if not block:
                    raise RuntimeError("Truncated repaired partition")
                previous = target.read(len(block))
                if block != previous:
                    target.seek(-len(block), 1)
                    target.write(block)
                    target.flush()
                    changed += 1
                remaining -= len(block)
            os.fsync(target.fileno())
        print(f"Repaired partition committed; changed chunks: {changed}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--disk", required=True, type=Path)
    parser.add_argument("--log", required=True, type=Path)
    parser.add_argument("--backup", type=Path, help="Enables repair; preserve this image")
    options = parser.parse_args()
    check(options.disk, options.log, options.backup)
