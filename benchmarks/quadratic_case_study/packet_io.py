"""Lossless bounded campaign archives. Input archives retain their original schema."""
from __future__ import annotations
import hashlib, io, json, lzma, shutil, tarfile
from pathlib import Path, PurePosixPath
from campaign import digest

MAX_PART = 48 * 1024**2
MAX_COMPRESSED = 512 * 1024**2
MAX_UNCOMPRESSED = 32 * 1024**3
XZ_MEMORY = 128 * 1024**2


def relative_name(name):
    path = PurePosixPath(name)
    if not name or path.is_absolute() or '..' in path.parts or str(path) != name:
        raise ValueError('Unsafe packet path')
    return path


class PartWriter:
    def __init__(self, output, name, allowance, part_limit=MAX_PART):
        self.output, self.name, self.allowance = output, name, allowance
        self.part_limit = part_limit
        self.parts = []; self.total = 0; self.whole = hashlib.sha256()
        self.stream = None; self.size = 0

    def write(self, data):
        if self.total + len(data) > self.allowance:
            raise ValueError('Compressed campaign byte budget exceeded')
        view = memoryview(data); consumed = 0
        while consumed < len(view):
            if self.stream is None:
                name = self.name + f'.part{len(self.parts)+1:04d}'
                self.stream = (self.output/name).open('xb')
                self.part_name = name; self.part_hash = hashlib.sha256(); self.size = 0
            amount = min(self.part_limit-self.size, len(view)-consumed)
            block = view[consumed:consumed+amount]
            self.stream.write(block); self.whole.update(block); self.part_hash.update(block)
            consumed += amount; self.total += amount; self.size += amount
            if self.size == self.part_limit: self.finish_part()
        return consumed

    def flush(self):
        if self.stream is not None: self.stream.flush()

    def finish_part(self):
        if self.stream is not None:
            self.stream.close(); self.stream = None
            self.parts.append(dict(name=self.part_name, size=self.size, sha256=self.part_hash.hexdigest()))

    def finish(self):
        self.finish_part()
        return dict(codec='xz', size=self.total, sha256=self.whole.hexdigest(), parts=self.parts)


def write_archive(root, paths, output, name, allowance, *, part_limit=MAX_PART):
    writer = PartWriter(output, name, allowance, part_limit)
    try:
        with lzma.LZMAFile(writer, 'w', format=lzma.FORMAT_XZ, preset=6) as compressed:
            with tarfile.open(fileobj=compressed, mode='w|', format=tarfile.PAX_FORMAT) as bundle:
                for relative in sorted(paths):
                    relative_name(str(relative)); path = root/relative
                    if not path.is_file() or path.is_symlink(): raise ValueError('Unexpected archive input')
                    item = tarfile.TarInfo(str(relative)); item.size = path.stat().st_size
                    item.mode = 0o644; item.uid = item.gid = 0; item.mtime = 0
                    with path.open('rb') as source: bundle.addfile(item, source)
        return writer.finish()
    finally:
        writer.finish_part()


def compressed_chunks(packet, archive):
    whole = hashlib.sha256(); total = 0
    for part in archive['parts']:
        path = packet/part['name']; part_hash = hashlib.sha256(); size = 0
        with path.open('rb') as stream:
            while block := stream.read(1024**2):
                whole.update(block); part_hash.update(block); size += len(block); total += len(block)
                yield block
        if size != part['size'] or part_hash.hexdigest() != part['sha256']:
            raise ValueError('Packet part identity mismatch')
    if total != archive['size'] or whole.hexdigest() != archive['sha256']:
        raise ValueError('Logical archive identity mismatch')


class DecodedArchive(io.RawIOBase):
    def __init__(self, chunks, allowance):
        self.chunks = iter(chunks); self.allowance = allowance; self.total = 0
        self.decoder = lzma.LZMADecompressor(format=lzma.FORMAT_XZ, memlimit=XZ_MEMORY)
        self.finished = False

    def readable(self): return True

    def readinto(self, buffer):
        if self.finished: return 0
        while True:
            if self.decoder.needs_input:
                try: block = next(self.chunks)
                except StopIteration: raise ValueError('Truncated compressed archive') from None
            else: block = b''
            data = self.decoder.decompress(block, max_length=len(buffer))
            self.total += len(data)
            if self.total > self.allowance: raise ValueError('Decoded archive allocation allowance exceeded')
            if self.decoder.eof:
                if self.decoder.unused_data or next(self.chunks, None) is not None:
                    raise ValueError('Trailing compressed archive data')
                self.finished = True
            if data:
                buffer[:len(data)] = data
                return len(data)
            if self.finished: return 0


def extract_v2(packet, output, index):
    files = index['files']; archives = index['archives']; total = 0; names = set()
    for name, record in files.items():
        relative_name(name)
        if not isinstance(record['size'], int) or record['size'] < 0:
            raise ValueError('Invalid member byte count')
        total += record['size']
    if total != index['uncompressed_bytes'] or total > MAX_UNCOMPRESSED:
        raise ValueError('Total uncompressed packet allowance exceeded')
    compressed = 0
    for name, archive in archives.items():
        if len(relative_name(name).parts) != 1 or archive['codec'] != 'xz':
            raise ValueError('Unexpected logical archive')
        subtotal = 0
        for part in archive['parts']:
            path = relative_name(part['name'])
            if len(path.parts) != 1 or part['name'] in names or not 0 < part['size'] <= MAX_PART:
                raise ValueError('Unsafe or oversized packet part')
            names.add(part['name']); subtotal += part['size']
            physical = packet/part['name']
            if physical.is_symlink() or physical.stat().st_size != part['size']:
                raise ValueError('Packet part size mismatch')
        if subtotal != archive['size']: raise ValueError('Archive byte count mismatch')
        compressed += subtotal
    if compressed != index['compressed_bytes'] or compressed > MAX_COMPRESSED:
        raise ValueError('Compressed campaign byte budget exceeded')
    if output.exists(): raise ValueError('Refuse existing extracted packet')
    output.parent.mkdir(parents=True, exist_ok=True)
    if shutil.disk_usage(output.parent).free < total + 1024**3:
        raise ValueError('Insufficient free disk for retained raw packet plus headroom')
    output.mkdir(); seen = set()
    for archive in archives.values():
        # Include bounded tar headers/padding in the decompression allowance.
        raw = DecodedArchive(compressed_chunks(packet, archive), total + len(files)*2048 + 1024**2)
        with io.BufferedReader(raw) as stream:
            with tarfile.open(fileobj=stream, mode='r|') as bundle:
                for item in bundle:
                    name = item.name; relative_name(name)
                    if not item.isfile() or name in seen or name not in files:
                        raise ValueError('Unsafe, duplicate or unexpected archive member')
                    if item.size != files[name]['size']: raise ValueError('Member size mismatch')
                    seen.add(name); path = output/name; path.parent.mkdir(parents=True, exist_ok=True)
                    h = hashlib.sha256()
                    with bundle.extractfile(item) as source, path.open('xb') as target:
                        while block := source.read(1024**2): h.update(block); target.write(block)
                    if h.hexdigest() != files[name]['sha256']: raise ValueError('Member hash mismatch')
            while padding := stream.read(1024**2):
                if any(padding): raise ValueError('Trailing non-padding archive bytes')
    if seen != set(files): raise ValueError('Packet member inventory mismatch')
