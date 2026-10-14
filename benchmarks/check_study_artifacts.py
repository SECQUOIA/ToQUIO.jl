"""Verify and safely unpack the public study; requires Python 3.11+ stdlib only."""
import gzip
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys
import tarfile

LIMIT = 512 * 1024 * 1024


def verify_and_extract(source, destination):
    checksums = json.loads((source / "checksums.json").read_text())
    for name, expected in checksums["archives"].items():
        path = source / name
        if path.parent != source or path.stat().st_size > LIMIT:
            raise ValueError("Invalid archive name or size")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != expected["sha256"] or path.stat().st_size != expected["bytes"]:
            raise ValueError("Published archive checksum differs")
    with tarfile.open(source / "campaign.tar.gz", "r:gz") as archive:
        members, total = [], 0
        for member in archive:
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or not (member.isfile() or member.isdir()):
                raise ValueError("Unsafe archive member")
            total += member.size
            members.append(member)
            if total > LIMIT or len(members) > 5000:
                raise ValueError("Archive exceeds the frozen extraction allowance")
        destination.mkdir(parents=True, exist_ok=False)
        archive.extractall(destination, members=members, filter="data")


def compare(source, generated):
    with gzip.open(source / "statistics.toml.gz", "rb") as stream:
        expected = stream.read(LIMIT + 1)
    if len(expected) > LIMIT or expected != (generated / "statistics.toml").read_bytes():
        raise ValueError("Regenerated statistics differ")
    if (source / "evaluation.csv").read_bytes() != (generated / "evaluation.csv").read_bytes():
        raise ValueError("Regenerated CSV differs")
    print("Published statistics and CSV reproduced byte for byte")


if __name__ == "__main__":
    mode, source, target = sys.argv[1:]
    action = {"extract": verify_and_extract, "compare": compare}[mode]
    action(Path(source).resolve(), Path(target).resolve())
