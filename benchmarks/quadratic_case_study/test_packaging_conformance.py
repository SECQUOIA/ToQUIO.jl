import json
from pathlib import Path
import tempfile
import unittest
from campaign import digest, STUDY
from packaging_conformance import (
    compressed_allowance, qualification, ORIGINAL_COMPRESSED, MAX_COMPRESSED, MANIFEST)


def fixture(root, cell_name='fixture.toml'):
    producing, previous, current = 'a'*40, 'b'*40, 'c'*40
    (root/'run.toml').write_text(f'source_commit="{producing}"\n')
    protocol = root/'source'/STUDY/'protocol.toml'
    protocol.parent.mkdir(parents=True, exist_ok=True)
    protocol.write_text(f'[resources]\nartifact_bytes={ORIGINAL_COMPRESSED}\n')
    (root/'analysis-files.json').write_text(json.dumps(dict(postprocessing_commit=current)))
    history = root/'analysis-history'/previous
    history.mkdir(parents=True)
    decoder_name=str(STUDY/'packet_io.py')
    decoder=history/'analysis-source'/decoder_name
    decoder.parent.mkdir(parents=True)
    decoder.write_text('# manufactured archived decoder source\n')
    (history/'analysis-files.json').write_text(json.dumps(dict(
        postprocessing_commit=previous, producing_commit=producing,
        files={decoder_name:dict(size=decoder.stat().st_size,sha256=digest(decoder))})))
    probe_input = root/'cells'/cell_name
    probe_input.parent.mkdir(exist_ok=True)
    if not probe_input.exists():probe_input.write_bytes(b'retained actual input bytes\n')
    directory = root/'processes/packaging'
    directory.mkdir(parents=True)
    log = directory/'failed.log'
    log.write_text('ValueError: Compressed campaign byte budget exceeded\n')
    failure = directory/'failed.json'
    failure.write_text(json.dumps(dict(kind='failed-packaging-attempt',
        source_commit=producing, postprocessing_commit=previous,
        terminal_worker=dict(Running=False, ExitCode=1, OOMKilled=False),
        index_exists=False, numerical_measurements_repeated=False,
        partial_compressed_bytes=100, parts={'example':dict(bytes=100)},
        docker_log_sha256=digest(log))))
    script = directory/'probe.py'
    script.write_text('# manufactured probe-source identity\n')
    probe = directory/'probe.json'
    controls={'memory.max':str(4*1024**3), 'memory.swap.max':'0',
              'memory.swap.current':'0', 'cpu.max':'100000 100000'}
    probe.write_text(json.dumps(dict(status='PASS', full_packet_fit_established=False,
        numerical_measurements_repeated=False, input=str(probe_input.relative_to(root)),
        effective_controls_before=controls, effective_controls_after=controls,
        input_sha256=digest(probe_input), probe_source_sha256=digest(script),
        archived_decoder_source_sha256=digest(decoder),
        results=[dict(preset=p, raw_bytes=probe_input.stat().st_size,
            original_sha256=digest(probe_input), compressed_bytes=n,
            decoder_memory_allowance=128*1024**2,
            effective_controls_after=controls,
            existing_archived_decoder_compatible=True) for p,n in ((6,8),(9,9))])))
    files = {key:dict(path=str(path.relative_to(root)), size=path.stat().st_size,
        sha256=digest(path)) for key,path in dict(failed_attempt=failure,
        failure_log=log, preset_probe=probe, probe_source=script).items()}
    record = dict(schema_version=1, kind='compressed-artifact-allowance-amendment',
        producing_commit=producing, previous_postprocessing_commit=previous,
        original_compressed_bytes=ORIGINAL_COMPRESSED, amended_compressed_bytes=MAX_COMPRESSED,
        original_budget_conformance='failed', reason='Retain complete observations', files=files)
    write_manifest(root, record)
    return record


def write_manifest(root, record):
    (root/MANIFEST).write_text(json.dumps(record, sort_keys=True)+'\n')
    (root/'postprocessing-amendment.toml').write_text(
        'kind="compressed-artifact-allowance-amendment"\n'
        f'previous_postprocessing_commit="{"b"*40}"\n'
        f'postprocessing_commit="{"c"*40}"\n'
        f'original_compressed_byte_allowance={ORIGINAL_COMPRESSED}\n'
        f'compressed_byte_allowance={MAX_COMPRESSED}\n'
        f'packaging_conformance_sha256="{digest(root/MANIFEST)}"\n')


class PackagingAllowance(unittest.TestCase):
    def test_original_protocol_still_applies_without_an_amendment(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            self.assertEqual(compressed_allowance(root), ORIGINAL_COMPRESSED)
            self.assertIsNone(qualification(root))

    def test_bound_amendment_retains_failed_original_disposition(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); fixture(root)
            self.assertEqual(compressed_allowance(root), MAX_COMPRESSED)
            result=qualification(root)
            self.assertEqual(result['original_budget_conformance'], 'failed')
            self.assertEqual(result['amended_packet_fit'],
                'requires-separate-complete-packet-verification')

    def test_changed_missing_or_inconsistent_evidence_is_rejected(self):
        for mutation in ('log', 'probe', 'binding', 'protocol', 'history',
                         'cap', 'disposition', 'original-input', 'path',
                         'orphan', 'decoder-hash', 'probe-controls'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temp:
                root=Path(temp); record=fixture(root)
                if mutation=='log':(root/'processes/packaging/failed.log').write_text('changed')
                elif mutation=='probe':(root/'processes/packaging/probe.json').unlink()
                elif mutation=='binding':(root/'postprocessing-amendment.toml').unlink()
                elif mutation=='protocol':
                    (root/'source'/STUDY/'protocol.toml').write_text('[resources]\nartifact_bytes=1\n')
                elif mutation=='history':
                    (root/'analysis-history'/('b'*40)/'analysis-files.json').unlink()
                elif mutation=='original-input':(root/'cells/fixture.toml').write_text('changed')
                elif mutation=='orphan':
                    (root/'postprocessing-amendment.toml').unlink()
                    (root/MANIFEST).unlink()
                elif mutation in ('decoder-hash','probe-controls'):
                    path=root/'processes/packaging/probe.json'
                    proof=json.loads(path.read_text())
                    if mutation=='decoder-hash':proof['archived_decoder_source_sha256']='0'*64
                    else:proof['effective_controls_before']['memory.swap.max']='max'
                    path.write_text(json.dumps(proof))
                    record['files']['preset_probe'].update(size=path.stat().st_size,sha256=digest(path))
                    write_manifest(root,record)
                else:
                    if mutation=='cap':record['amended_compressed_bytes']=MAX_COMPRESSED+1
                    elif mutation=='disposition':record['original_budget_conformance']='passed'
                    else:record['files']['failure_log']['path']='../escape'
                    write_manifest(root,record)
                with self.assertRaises((ValueError, FileNotFoundError)):
                    compressed_allowance(root)

    def test_unamended_packet_cannot_claim_the_larger_allowance(self):
        from test_packet_io import actual_tool_campaign
        from pack import pack_campaign, extract_packet
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);campaign=actual_tool_campaign(root);packet=root/'packet'
            pack_campaign(campaign,packet)
            index=json.loads((packet/'index.json').read_text())
            index['compressed_byte_allowance']=MAX_COMPRESSED
            (packet/'index.json').write_text(json.dumps(index))
            with self.assertRaisesRegex(ValueError, 'allowance differs'):
                extract_packet(packet,root/'out')

    def test_amended_packet_full_and_report_view_roundtrip(self):
        import shutil
        from test_packet_io import actual_tool_campaign
        from pack import pack_campaign, extract_packet, extract_analysis
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);campaign=actual_tool_campaign(root)
            original=json.loads((campaign/'analysis-files.json').read_text())
            record=fixture(campaign, cell_name='fixture-facility--native.toml')
            original['postprocessing_commit']='c'*40
            (campaign/'analysis-files.json').write_text(json.dumps(original))
            history=campaign/'analysis-history'/('b'*40)
            shutil.copytree(campaign/'analysis-source', history/'analysis-source',dirs_exist_ok=True)
            previous=dict(original,postprocessing_commit='b'*40)
            (history/'analysis-files.json').write_text(json.dumps(previous))
            (history/'run.toml').write_text('source_commit="'+'a'*40+'"\n')
            probe_path=campaign/'processes/packaging/probe.json'
            probe=json.loads(probe_path.read_text())
            probe['archived_decoder_source_sha256']=digest(history/'analysis-source'/STUDY/'packet_io.py')
            probe_path.write_text(json.dumps(probe))
            record['files']['preset_probe'].update(size=probe_path.stat().st_size,sha256=digest(probe_path))
            write_manifest(campaign,record)
            packet=root/'packet';pack_campaign(campaign,packet)
            index=json.loads((packet/'index.json').read_text())
            self.assertEqual(index['compressed_byte_allowance'], MAX_COMPRESSED)
            extract_analysis(packet,root/'bootstrap')
            self.assertTrue((root/'bootstrap/analysis-source'/STUDY/'packaging_conformance.py').is_file())
            for name,view in (('full',False),('view',True)):
                output=root/name
                extract_packet(packet,output,report_view=view)
                self.assertEqual(compressed_allowance(output),MAX_COMPRESSED)
                self.assertEqual(qualification(output),qualification(campaign))
