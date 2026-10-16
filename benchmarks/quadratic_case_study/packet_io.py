"""Lossless bounded campaign archives. Input archives retain their original schema."""
from __future__ import annotations
import hashlib, io, json, lzma, shutil, tarfile
from pathlib import Path, PurePosixPath
from campaign import digest, read_toml
from packaging_conformance import MAX_COMPRESSED, ORIGINAL_COMPRESSED

MAX_PART = 48 * 1024**2
MAX_UNCOMPRESSED = 64 * 1024**3
MAX_REPORT_VIEW = 8 * 1024**3
VIEW_RESERVED = {'.report-view', 'extraction-index.json', 'extraction-view.json'}
STUDY = Path('benchmarks/quadratic_case_study')
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
            try: data = self.decoder.decompress(block, max_length=len(buffer))
            except lzma.LZMAError: raise ValueError('Invalid compressed archive') from None
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


def extract_v2(packet, output, index, *, report_view=False):
    files = index['files']; archives = index['archives']; total = 0; names = set()
    for name, record in files.items():
        relative_name(name)
        if name in VIEW_RESERVED: raise ValueError('Reserved report-view path in raw packet')
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
    allowance = index.get('compressed_byte_allowance', ORIGINAL_COMPRESSED)
    if (type(allowance) is not int or not 0 < allowance <= MAX_COMPRESSED or
            compressed != index['compressed_bytes'] or compressed > allowance):
        raise ValueError('Compressed campaign byte budget exceeded')
    index_bytes = None; projection = None
    if report_view:
        index_bytes = (packet/'index.json').read_bytes()
        if json.loads(index_bytes) != index: raise ValueError('Retained packet index differs')
        projection = projection_sources(index)
    if output.exists(): raise ValueError('Refuse existing extracted packet')
    output.parent.mkdir(parents=True, exist_ok=True)
    required = min(total, MAX_REPORT_VIEW) if report_view else total
    if shutil.disk_usage(output.parent).free < required + 1024**3:
        raise ValueError('Insufficient free disk for retained raw packet or view plus headroom')
    if report_view and MAX_REPORT_VIEW < 65: raise ValueError('Report-view byte allowance exceeded')
    output.mkdir(); seen = set(); view_files = {}; written = 65 if report_view else 0
    if report_view: (output/'.report-view').write_text(hashlib.sha256(index_bytes).hexdigest()+'\n')
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
                    h = hashlib.sha256(); view_hash = hashlib.sha256(); raw_size = 0; view_size = 0
                    project = report_view and Path(name).parts[0]=='cells' and name.endswith('.toml')
                    with bundle.extractfile(item) as source, path.open('xb') as target:
                        def counted_blocks():
                            nonlocal raw_size
                            if project:
                                from report import bounded_cell_lines
                                blocks = bounded_cell_lines(source)
                            else: blocks = iter(lambda: source.read(1024**2), b'')
                            for block in blocks:
                                h.update(block); raw_size += len(block)
                                yield block
                        blocks = counted_blocks()
                        if project:
                            from report import projected_cell_bytes
                            blocks = projected_cell_bytes(blocks)
                        for block in blocks:
                            written += len(block); view_size += len(block)
                            if report_view and written > MAX_REPORT_VIEW:
                                raise ValueError('Report-view byte allowance exceeded')
                            view_hash.update(block); target.write(block)
                    if raw_size != item.size or h.hexdigest() != files[name]['sha256']:
                        raise ValueError('Member hash or byte count mismatch')
                    if report_view:
                        view_files[name] = dict(original_size=item.size, original_sha256=h.hexdigest(),
                            view_size=view_size, view_sha256=view_hash.hexdigest(), projected=project)
            while padding := stream.read(1024**2):
                if any(padding): raise ValueError('Trailing non-padding archive bytes')
    if seen != set(files): raise ValueError('Packet member inventory mismatch')

    if report_view:
        manifest = dict(schema_version=1, complete=True, kind='derived-report-view',
            projection_version='omit-compiler-metadata-v1', projection_sources=projection,
            producing_commit=index['source_commit'], postprocessing_commit=index['postprocessing_commit'],
            packet_index_sha256=hashlib.sha256(index_bytes).hexdigest(), files=view_files)
        manifest_bytes = (json.dumps(manifest,sort_keys=True,indent=2)+'\n').encode()
        if written + len(index_bytes) + len(manifest_bytes) > MAX_REPORT_VIEW:
            raise ValueError('Report-view metadata exceeds byte allowance')
        (output/'extraction-index.json').write_bytes(index_bytes)
        (output/'extraction-view.json').write_bytes(manifest_bytes)
        verify_report_view(output)


def projection_sources(index):
    """Bind the actual extraction implementation to the archived analysis revision."""
    import report
    actual = {'packet_io.py':digest(Path(__file__)), 'report.py':digest(Path(report.__file__))}
    for name, checksum in actual.items():
        entry = index['files'].get(str(Path('analysis-source')/STUDY/name))
        if entry is None or entry['sha256'] != checksum:
            raise ValueError('Use the archived postprocessing tools for this report-view version')
    return actual


def verify_report_view(root, *, required=False):
    marker = root/'.report-view'; manifest_path = root/'extraction-view.json'
    reserved = [root/name for name in VIEW_RESERVED]
    if any(path.is_symlink() for path in reserved): raise ValueError('Unexpected report-view provenance link')
    if not any(path.exists() for path in reserved):
        if required: raise ValueError('Verified report view required')
        return None
    try:
        manifest = json.loads(manifest_path.read_text())
        index_bytes = (root/'extraction-index.json').read_bytes(); index = json.loads(index_bytes)
        expected_hash = hashlib.sha256(index_bytes).hexdigest()
        if marker.read_text() != expected_hash+'\n': raise ValueError('Report-view index binding differs')
    except (FileNotFoundError, json.JSONDecodeError):
        raise ValueError('Incomplete report view') from None
    if (manifest.get('schema_version')!=1 or manifest.get('complete') is not True or
            manifest.get('kind')!='derived-report-view' or
            manifest.get('projection_version')!='omit-compiler-metadata-v1' or
            manifest.get('packet_index_sha256')!=expected_hash or
            manifest.get('producing_commit')!=index['source_commit'] or
            manifest.get('postprocessing_commit')!=index['postprocessing_commit'] or
            set(manifest['files'])!=set(index['files'])):
        raise ValueError('Report-view provenance differs')
    producer = read_toml(root/'run.toml')['source_commit']
    analysis = json.loads((root/'analysis-files.json').read_text())
    if (manifest['producing_commit']!=producer or analysis['producing_commit']!=producer or
            manifest['postprocessing_commit']!=analysis['postprocessing_commit']):
        raise ValueError('Report-view source revisions differ from retained identity')
    for name, checksum in manifest['projection_sources'].items():
        if name not in ('report.py','packet_io.py'):
            raise ValueError('Unexpected projection implementation')
        if index['files'][str(Path('analysis-source')/STUDY/name)]['sha256'] != checksum:
            raise ValueError('Report-view analysis revision differs')
    if set(manifest['projection_sources'])!={'report.py','packet_io.py'}:
        raise ValueError('Missing projection implementation')
    actual = set(); total = 0
    for path in root.rglob('*'):
        if path.is_symlink(): raise ValueError('Unexpected link in report view')
        if path.is_file(): actual.add(str(path.relative_to(root))); total += path.stat().st_size
    if actual != set(index['files']) | VIEW_RESERVED or total > MAX_REPORT_VIEW:
        raise ValueError('Report-view file inventory or byte allowance differs')
    for name, view in manifest['files'].items():
        relative_name(name); original = index['files'][name]; path = root/name
        project = Path(name).parts[0]=='cells' and name.endswith('.toml')
        if (view['projected'] is not project or view['original_size']!=original['size'] or
                view['original_sha256']!=original['sha256'] or path.stat().st_size!=view['view_size'] or
                digest(path)!=view['view_sha256'] or
                (not project and (view['view_sha256']!=original['sha256'] or view['view_size']!=original['size']))):
            raise ValueError('Changed report-view bytes or original binding')
    return manifest
