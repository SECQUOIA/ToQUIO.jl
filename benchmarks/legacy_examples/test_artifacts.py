import hashlib
import io
from pathlib import Path
import tarfile
import tempfile
import unittest

import report


class IntegrityTests(unittest.TestCase):
    def test_corrupted_packet_is_rejected_before_extraction(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            packet = root / "bad.tar.gz"
            packet.write_bytes(b"changed bytes")
            with self.assertRaisesRegex(ValueError, "SHA256 mismatch"):
                report.unpack(packet, "0" * 64, root / "output")
            self.assertFalse((root / "output").exists())

    def test_path_traversal_is_rejected_even_with_matching_outer_digest(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            packet = root / "bad.tar.gz"
            with tarfile.open(packet, "w:gz") as archive:
                item = tarfile.TarInfo("../escaped")
                item.size = 1
                archive.addfile(item, io.BytesIO(b"x"))
            digest = hashlib.sha256(packet.read_bytes()).hexdigest()
            with self.assertRaisesRegex(ValueError, "packet members"):
                report.unpack(packet, digest, root / "output")
            self.assertFalse((root / "escaped").exists())


if __name__ == "__main__":
    unittest.main()
