import gzip
import hashlib
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

from check_study_artifacts import verify_and_extract, compare


class StudyArtifactTests(unittest.TestCase):
    def fixture(self, root, member="ledger.toml"):
        source = root / "source"
        source.mkdir()
        with tarfile.open(source / "campaign.tar.gz", "w:gz") as archive:
            item = tarfile.TarInfo(member)
            item.size = 3
            archive.addfile(item, io.BytesIO(b"abc"))
        (source / "statistics.toml.gz").write_bytes(gzip.compress(b"a=1\n"))
        checksums = {"archives": {name: {"bytes": (source / name).stat().st_size,
            "sha256": hashlib.sha256((source / name).read_bytes()).hexdigest()}
            for name in ("campaign.tar.gz", "statistics.toml.gz")},
            "statistics_sha256": hashlib.sha256(b"a=1\n").hexdigest()}
        (source / "checksums.json").write_text(json.dumps(checksums))
        return source, checksums

    def test_valid_extraction_and_existing_destination_refusal(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, _ = self.fixture(root)
            verify_and_extract(source, root / "extracted")
            self.assertEqual((root / "extracted" / "ledger.toml").read_bytes(), b"abc")
            with self.assertRaises(FileExistsError):
                verify_and_extract(source, root / "extracted")

    def test_missing_archive_hash_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, checksums = self.fixture(root)
            del checksums["archives"]["campaign.tar.gz"]
            (source / "checksums.json").write_text(json.dumps(checksums))
            with self.assertRaisesRegex(ValueError, "exactly"):
                verify_and_extract(source, root / "extracted")

    def test_traversal_is_rejected_despite_valid_compressed_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, _ = self.fixture(root, "../outside")
            with self.assertRaisesRegex(ValueError, "Unsafe"):
                verify_and_extract(source, root / "extracted")
            self.assertFalse((root / "outside").exists())

    def test_uncompressed_hash_is_checked_before_report_comparison(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, checksums = self.fixture(root)
            checksums["statistics_sha256"] = "0" * 64
            (source / "checksums.json").write_text(json.dumps(checksums))
            with self.assertRaisesRegex(ValueError, "Uncompressed"):
                compare(source, root / "absent")


    def test_documentation_is_required(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            parent = root / "repo" / "benchmarks" / "results"
            parent.mkdir(parents=True)
            source, _ = self.fixture(parent)
            generated = root / "generated"
            generated.mkdir()
            for target in (source, generated):
                (target / "evaluation.csv").write_text("a\n1\n")
                (target / "TABLES.md").write_text("table\n")
                (target / "hardware_subset.toml").write_text("schema_version=1\n")
            (generated / "statistics.toml").write_bytes(b"a=1\n")
            (source / "hardware_subset.json").write_text('{"schema_version":1}')
            with self.assertRaisesRegex(ValueError, "documentation"):
                compare(source, generated)


if __name__ == "__main__":
    unittest.main()
