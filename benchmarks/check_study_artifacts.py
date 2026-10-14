"""Verify and safely unpack the public study; requires Python 3.11.4+ stdlib only."""
import gzip
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys
import tomllib
import tarfile

LIMIT = 512 * 1024 * 1024


def verify_and_extract(source, destination):
    checksums = json.loads((source / "checksums.json").read_text())
    if set(checksums["archives"]) != {"campaign.tar.gz", "statistics.toml.gz"}:
        raise ValueError("Expected exactly the two published archives")
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


def diagnostic_differences(left, right, path="root", limit=20):
    differences = []
    if isinstance(left, dict) and isinstance(right, dict):
        for key in sorted(left.keys() | right.keys()):
            if key not in left or key not in right:
                differences.append((path + "." + key, "missing key"))
            else:
                differences.extend(diagnostic_differences(left[key], right[key], path + "." + key, limit))
            if len(differences) >= limit:
                break
    elif isinstance(left, list) and isinstance(right, list):
        if len(left) != len(right):
            differences.append((path, f"length {len(left)} != {len(right)}"))
        for index, (a, b) in enumerate(zip(left, right)):
            differences.extend(diagnostic_differences(a, b, f"{path}[{index}]", limit))
            if len(differences) >= limit:
                break
    elif left != right:
        differences.append((path, f"expected={str(left)[:120]} actual={str(right)[:120]}"))
    return differences[:limit]


def compare(source, generated):
    with gzip.open(source / "statistics.toml.gz", "rb") as stream:
        expected = stream.read(LIMIT + 1)
    digest = json.loads((source / "checksums.json").read_text())["statistics_sha256"]
    if hashlib.sha256(expected).hexdigest() != digest:
        raise ValueError("Uncompressed statistics checksum differs")
    actual = (generated / "statistics.toml").read_bytes()
    if len(expected) > LIMIT or expected != actual:
        for path, detail in diagnostic_differences(tomllib.loads(expected.decode()), tomllib.loads(actual.decode())):
            print("REPORT DIFFERENCE", path, detail)
        raise ValueError("Regenerated statistics differ")
    if (source / "evaluation.csv").read_bytes() != (generated / "evaluation.csv").read_bytes():
        raise ValueError("Regenerated CSV differs")
    for name in ("TABLES.md", "hardware_subset.toml"):
        if (source / name).read_bytes() != (generated / name).read_bytes():
            raise ValueError("Regenerated disclosure tables/subset differ")
    subset = tomllib.loads((generated / "hardware_subset.toml").read_text())
    if subset != json.loads((source / "hardware_subset.json").read_text()):
        raise ValueError("Hardware JSON differs from generated subset")
    docs = source.parents[2] / "docs" / "src"
    if not docs.is_dir():
        raise ValueError("Required documentation directory is absent")
    if docs.is_dir():
        for name, doc in (("REPORT.md", "classical_study.md"), ("TABLES.md", "TABLES.md")):
            if (source / name).read_bytes() != (docs / doc).read_bytes():
                raise ValueError("Documentation differs from the published study")
    print("Published statistics, CSV, tables, subset and docs reproduced")


if __name__ == "__main__":
    mode, source, target = sys.argv[1:]
    action = {"extract": verify_and_extract, "compare": compare}[mode]
    action(Path(source).resolve(), Path(target).resolve())
