import tempfile, unittest
from pathlib import Path
from campaign import digest
from packet_io import write_archive, extract_v2, MAX_UNCOMPRESSED
from report import read_cell_record


class StreamingCellReader(unittest.TestCase):
    def test_omits_only_expanded_metadata_and_preserves_other_fields(self):
        import tomllib
        text='''status="measured"
kind="structural"
[compiler]
arm="example"
[compiler.metadata]
ignored="unused"
[[compiler.metadata.constraint_encodings]]
coefficient=2
[[compiler.metadata.constraint_encodings.terms]]
coefficient=3
variables=[1,2]
[[compiler.metadata.constraint_encodings.terms]]
coefficient=4
variables=[2,3]
[compiler.metadata_extra]
retained=7
[[maps]]
weights=[1,2]
positions=[1,2]
[metrics]
active_variables=2
'''
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'cell.toml';path.write_text(text);before=digest(path)
            full=tomllib.loads(text);del full['compiler']['metadata']
            self.assertEqual(read_cell_record(path),full)
            self.assertEqual(digest(path),before)
    def test_rejects_unbounded_line(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'cell.toml';path.write_text('x="'+'a'*(8*1024**2)+'"\n')
            with self.assertRaisesRegex(ValueError,'line exceeds'):read_cell_record(path)


class LosslessMultipartPacket(unittest.TestCase):
    def fixture(self,root):
        source=root/'source';source.mkdir();packet=root/'packet';packet.mkdir()
        (source/'one').write_bytes(bytes(range(256))*32)
        (source/'nested').mkdir();(source/'nested/two').write_bytes(b'raw diagnostics'*100)
        paths=[Path('one'),Path('nested/two')]
        archive=write_archive(source,paths,packet,'example.tar.xz',1024**2,part_limit=80)
        self.assertGreater(len(archive['parts']),1)
        files={str(p):dict(size=(source/p).stat().st_size,sha256=digest(source/p)) for p in paths}
        index=dict(schema_version=2,archives={'example.tar.xz':archive},files=files,
            compressed_bytes=archive['size'],uncompressed_bytes=sum(v['size'] for v in files.values()))
        return source,packet,index
    def test_lossless_deterministic_parts_and_byte_identity(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);source,packet,index=self.fixture(root)
            second=root/'second';second.mkdir()
            archive=write_archive(source,[Path(p) for p in index['files']],second,'example.tar.xz',1024**2,part_limit=80)
            self.assertEqual(archive,index['archives']['example.tar.xz'])
            for part in archive['parts']:self.assertEqual((packet/part['name']).read_bytes(),(second/part['name']).read_bytes())
            extract_v2(packet,root/'out',index)
            for name in index['files']:self.assertEqual((source/name).read_bytes(),(root/'out'/name).read_bytes())
            with self.assertRaisesRegex(ValueError,'existing'):extract_v2(packet,root/'out',index)
    def test_rejects_changed_part_hash_truncation_and_member_size(self):
        for mutation in ('hash','truncate','size','traversal','raw_budget'):
            with self.subTest(mutation=mutation),tempfile.TemporaryDirectory() as temp:
                root=Path(temp);_,packet,index=self.fixture(root)
                if mutation=='hash':index['archives']['example.tar.xz']['parts'][0]['sha256']='0'*64
                elif mutation=='truncate':
                    p=packet/index['archives']['example.tar.xz']['parts'][-1]['name'];p.write_bytes(p.read_bytes()[:-1])
                elif mutation=='size':index['files']['one']['size']+=1;index['uncompressed_bytes']+=1
                elif mutation=='traversal':index['files']['../escape']=index['files'].pop('one')
                else:index['uncompressed_bytes']=MAX_UNCOMPRESSED+1
                with self.assertRaises(ValueError):extract_v2(packet,root/'out',index)
                self.assertFalse((root/'escape').exists())

    def test_campaign_pack_uses_inventory_family_for_manufactured_ids(self):
        import json
        from freeze_analysis import TOOLS
        from campaign import STUDY
        from pack import pack_campaign,extract_packet
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);campaign=root/'campaign';campaign.mkdir()
            for name in ('source','inputs','cells'): (campaign/name).mkdir()
            (campaign/'inputs/inventory.toml').write_text(
                '[[instances]]\ninstance_id="fixture-facility"\nfamily="facility"\n')
            (campaign/'cells/fixture-facility--native.toml').write_text('status="measured"\n')
            (campaign/'run.toml').write_text('source_commit="'+'a'*40+'"\n')
            for name in ('environment.toml','plan.json','source-files.json','completion.json'):
                (campaign/name).write_text('{}')
            files={}
            for name in TOOLS:
                relative=str(STUDY/name);path=campaign/'analysis-source'/relative
                path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b'# frozen fixture\n')
                files[relative]=dict(size=path.stat().st_size,sha256=digest(path))
            (campaign/'analysis-files.json').write_text(json.dumps(dict(schema_version=1,
                producing_commit='a'*40,postprocessing_commit='b'*40,files=files)))
            pack_campaign(campaign,root/'packet');extract_packet(root/'packet',root/'out')
            self.assertEqual((root/'out/cells/fixture-facility--native.toml').read_bytes(),
                             (campaign/'cells/fixture-facility--native.toml').read_bytes())


if __name__=='__main__':unittest.main()
