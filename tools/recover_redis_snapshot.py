"""Export a live Redis RDB through diskless replication when its disk fails.

Use only with the scanner stopped and a private SSH forward. Recovery changes
Redis persistence settings in memory; it never flushes or changes stored keys.
The original VM disks must be retained. Validate the RDB with redis-check-rdb
before restoring it into a fresh Redis volume.
"""
import argparse
import hashlib
import os
from pathlib import Path
import socket


def send(sock, *args):
    values = [str(x).encode() for x in args]
    sock.sendall(b"*" + str(len(values)).encode() + b"\r\n" + b"".join(
        b"$" + str(len(v)).encode() + b"\r\n" + v + b"\r\n" for v in values))


def command(port, *args):
    with socket.create_connection(("127.0.0.1", port), timeout=30) as sock:
        send(sock, *args)
        reply = sock.makefile("rb").readline().strip()
        if reply != b"+OK":
            raise RuntimeError(f"Recovery setting {args[1]} was refused")


def export(port, output):
    if output.exists() or output.with_suffix(output.suffix + ".partial").exists():
        raise RuntimeError("Choose a new output path; existing backups are preserved")
    output.parent.mkdir(parents=True, exist_ok=True)
    # The broken AOF otherwise blocks commands. All changes are runtime-only.
    for key, value in (("appendonly", "no"), ("stop-writes-on-bgsave-error", "no"),
                       ("repl-diskless-sync", "yes"), ("repl-diskless-sync-delay", "0")):
        command(port, "CONFIG", "SET", key, value)
    partial = output.with_suffix(output.suffix + ".partial")
    with socket.create_connection(("127.0.0.1", port), timeout=60) as sock:
        stream = sock.makefile("rb")
        send(sock, "REPLCONF", "capa", "eof")
        if stream.readline().strip() != b"+OK":
            raise RuntimeError("Redis refused diskless EOF capability")
        send(sock, "SYNC")
        header = stream.readline().strip()
        while not header:
            header = stream.readline().strip()
        if not header.startswith(b"$"):
            raise RuntimeError("Redis refused diskless snapshot export")
        with partial.open("xb") as target:
            os.chmod(partial, 0o600)
            if header.startswith(b"$EOF:"):
                marker = header[5:]
                if len(marker) != 40:
                    raise RuntimeError("Invalid replication EOF marker")
                pending = b""
                while True:
                    block = stream.read1(65536)
                    if not block:
                        raise RuntimeError("Truncated diskless snapshot")
                    pending += block
                    index = pending.find(marker)
                    if index >= 0:
                        target.write(pending[:index])
                        break
                    if len(pending) > len(marker):
                        target.write(pending[:-len(marker)])
                        pending = pending[-len(marker):]
            else:
                remaining = int(header[1:])
                while remaining:
                    block = stream.read(min(remaining, 65536))
                    if not block:
                        raise RuntimeError("Truncated Redis snapshot")
                    target.write(block)
                    remaining -= len(block)
            target.flush()
            os.fsync(target.fileno())
    data = partial.read_bytes()
    if len(data) < 18 or not data.startswith(b"REDIS"):
        raise RuntimeError("Export is not an RDB; partial file retained")
    partial.rename(output)
    print(f"Snapshot: {output}")
    print(f"Bytes: {len(data)}; SHA256: {hashlib.sha256(data).hexdigest()}")
    print("RDB checksum validation is required before restore.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=16379)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    export(args.port, args.output)
