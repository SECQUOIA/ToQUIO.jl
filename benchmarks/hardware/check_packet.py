"""Compare every published offline artifact with a fresh generated packet."""
import hashlib
import json
from pathlib import Path
import sys


def compare(source: Path, generated: Path):
    hashes = json.loads((source / "checksums.json").read_text())
    expected = set(hashes) | {"checksums.json"}
    for folder in (source, generated):
        if {path.name for path in folder.iterdir()} != expected:
            raise ValueError("Readiness packet member set differs")
        for name, digest in hashes.items():
            path = folder / name
            if path.is_symlink() or not path.is_file():
                raise ValueError("Packet member is not a regular file")
            if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                raise ValueError(f"Packet checksum differs: {name}")
    for name in expected:
        if (source / name).read_bytes() != (generated / name).read_bytes():
            raise ValueError(f"Offline reproduction differs: {name}")
    print(f"All {len(expected)} offline artifacts reproduced exactly")


if __name__ == "__main__":
    compare(*(Path(arg) for arg in sys.argv[1:]))
