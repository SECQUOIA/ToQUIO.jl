"""Bind an explicit postmeasurement archive allowance to retained failure evidence."""
import json
from pathlib import Path
from campaign import digest, read_toml, STUDY

ORIGINAL_COMPRESSED = 512 * 1024**2
MAX_COMPRESSED = 1024**3
MANIFEST = Path('processes/packaging-conformance.json')
REQUIRED = {'failed_attempt', 'failure_log', 'preset_probe', 'probe_source'}


def bounded_json(path, maximum=128*1024):
    if path.is_symlink() or path.stat().st_size > maximum:
        raise ValueError('Invalid packaging provenance file')
    return json.loads(path.read_text())


def original_allowance(root):
    path = root/'source'/STUDY/'protocol.toml'
    value = (read_toml(path)['resources']['artifact_bytes']
             if path.is_file() else ORIGINAL_COMPRESSED)
    if type(value) is not int or not 0 < value <= MAX_COMPRESSED:
        raise ValueError('Invalid original compressed allowance')
    return value


def qualification(root):
    root = Path(root)
    amendment_path = root/'postprocessing-amendment.toml'
    amendment = read_toml(amendment_path) if amendment_path.is_file() else {}
    binding = amendment.get('packaging_conformance_sha256')
    if binding is None:
        retained = any(p.is_file() or p.is_symlink()
                       for p in (root/'processes/packaging').rglob('*'))
        if (root/MANIFEST).exists() or retained or 'compressed_byte_allowance' in amendment:
            raise ValueError('Unbound packaging allowance amendment')
        return None
    if (amendment.get('kind') != 'compressed-artifact-allowance-amendment' or
            digest(root/MANIFEST) != binding):
        raise ValueError('Changed packaging allowance amendment')
    record = bounded_json(root/MANIFEST)
    original = original_allowance(root)
    producing = read_toml(root/'run.toml')['source_commit']
    current = bounded_json(root/'analysis-files.json')['postprocessing_commit']
    previous = record.get('previous_postprocessing_commit', '')
    if (not isinstance(previous, str) or len(previous) != 40 or
            any(c not in '0123456789abcdef' for c in previous)):
        raise ValueError('Invalid previous packaging revision')
    history = bounded_json(root/'analysis-history'/previous/'analysis-files.json')
    if (record.get('schema_version') != 1 or
            record.get('kind') != 'compressed-artifact-allowance-amendment' or
            record.get('producing_commit') != producing or
            amendment.get('postprocessing_commit') != current or
            current == previous or
            history.get('postprocessing_commit') != previous or
            history.get('producing_commit') != producing or
            record.get('previous_postprocessing_commit') != amendment.get('previous_postprocessing_commit') or
            record.get('original_compressed_bytes') != original or
            record.get('amended_compressed_bytes') != MAX_COMPRESSED or
            amendment.get('original_compressed_byte_allowance') != original or
            amendment.get('compressed_byte_allowance') != MAX_COMPRESSED or
            record.get('original_budget_conformance') != 'failed' or
            not isinstance(record.get('reason'), str) or not record['reason'].strip()):
        raise ValueError('Invalid packaging allowance provenance')
    files = record.get('files', {})
    if not REQUIRED <= set(files):
        raise ValueError('Incomplete packaging failure evidence')
    paths = {}
    for name, entry in files.items():
        relative = Path(entry['path'])
        if (relative.is_absolute() or '..' in relative.parts or
                str(relative) != entry['path'] or
                relative.parts[:2] != ('processes', 'packaging')):
            raise ValueError('Unsafe packaging evidence path')
        path = root/relative
        if (path.is_symlink() or not path.resolve().is_relative_to(root.resolve()) or
                path.stat().st_size > 128*1024 or type(entry['size']) is not int or
                path.stat().st_size != entry['size'] or digest(path) != entry['sha256']):
            raise ValueError('Changed packaging failure evidence')
        paths[name] = path
    failure = bounded_json(paths['failed_attempt'])
    state = failure['terminal_worker']
    if (failure.get('kind') != 'failed-packaging-attempt' or
            failure.get('source_commit') != producing or
            failure.get('postprocessing_commit') != record['previous_postprocessing_commit'] or
            state['Running'] or state['ExitCode'] != 1 or state['OOMKilled'] or
            failure.get('index_exists') is not False or
            failure.get('numerical_measurements_repeated') is not False or
            not 0 < failure['partial_compressed_bytes'] <= original or
            failure['partial_compressed_bytes'] != sum(p['bytes'] for p in failure['parts'].values()) or
            failure['docker_log_sha256'] != digest(paths['failure_log']) or
            b'Compressed campaign byte budget exceeded' not in paths['failure_log'].read_bytes()):
        raise ValueError('Invalid original packaging failure')
    probe = bounded_json(paths['preset_probe'])
    decoder_name = str(STUDY/'packet_io.py')
    decoder = root/'analysis-history'/previous/'analysis-source'/decoder_name
    decoder_entry = history['files'][decoder_name]
    if (probe.get('archived_decoder_source_sha256') != decoder_entry['sha256'] or
            decoder.stat().st_size != decoder_entry['size'] or digest(decoder) != decoder_entry['sha256']):
        raise ValueError('Compression probe decoder differs from retained previous analysis')
    results = {r['preset']: r for r in probe['results']}
    if (probe.get('status') != 'PASS' or probe.get('full_packet_fit_established') is not False or
            probe.get('numerical_measurements_repeated') is not False or
            set(results) != {6, 9} or len(probe['results']) != 2 or
            results[9]['compressed_bytes'] <= results[6]['compressed_bytes'] or
            probe['probe_source_sha256'] != digest(paths['probe_source'])):
        raise ValueError('Invalid retained negative compression probe')
    relative = Path(probe['input'])
    if (relative.is_absolute() or '..' in relative.parts or not relative.parts or
            str(relative) != probe['input'] or relative.parts[0] != 'cells'):
        raise ValueError('Unsafe compression probe input')
    if (root/'.report-view').exists():
        original_entry = bounded_json(root/'extraction-index.json', 64*1024**2)['files'][str(relative)]
        size, sha256 = original_entry['size'], original_entry['sha256']
    else:
        size, sha256 = (root/relative).stat().st_size, digest(root/relative)
    if probe['input_sha256'] != sha256:
        raise ValueError('Compression probe input differs from retained original')
    for result in results.values():
        if (result['raw_bytes'] != size or result['original_sha256'] != sha256 or
                result['decoder_memory_allowance'] != 128*1024**2 or
                result.get('existing_archived_decoder_compatible') is not True):
            raise ValueError('Compression probe lacks bounded original-byte roundtrip')
    for controls in (probe['effective_controls_before'], probe['effective_controls_after'],
                     *(r['effective_controls_after'] for r in results.values())):
        if (controls['memory.max'] != str(4*1024**3) or controls['memory.swap.max'] != '0' or
                controls['memory.swap.current'] != '0' or controls['cpu.max'] != '100000 100000'):
            raise ValueError('Compression probe lacks intended effective resource controls')
    return dict(original_budget_conformance='failed', original_compressed_bytes=original,
        amended_compressed_bytes=MAX_COMPRESSED, manifest_sha256=binding,
        previous_postprocessing_commit=record['previous_postprocessing_commit'],
        failed_attempt_sha256=files['failed_attempt']['sha256'],
        negative_probe_sha256=files['preset_probe']['sha256'],
        amended_packet_fit='requires-separate-complete-packet-verification')


def compressed_allowance(root):
    record = qualification(root)
    return record['amended_compressed_bytes'] if record else original_allowance(Path(root))
