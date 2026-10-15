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



def actual_tool_campaign(root):
    import json
    from campaign import STUDY
    from freeze_analysis import TOOLS
    campaign=root/'campaign';campaign.mkdir()
    for name in ('source','inputs','cells'):(campaign/name).mkdir()
    (campaign/'inputs/inventory.toml').write_text('[[instances]]\ninstance_id="fixture-facility"\nfamily="facility"\n')
    (campaign/'cells/fixture-facility--native.toml').write_text('''status="measured"
kind="structural"
[compiler]
arm="native"
[compiler.metadata]
ignored="123"
[[compiler.metadata.constraint_encodings.terms]]
coefficient=7
indices=[1,2]
[metrics]
active_variables=2
''')
    (campaign/'run.toml').write_text('source_commit="'+'a'*40+'"\n')
    for name in ('environment.toml','plan.json','source-files.json','completion.json'):(campaign/name).write_text('{}')
    files={}
    for name in TOOLS:
        relative=str(STUDY/name);path=campaign/'analysis-source'/relative
        path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes((Path(__file__).parent/name).read_bytes())
        files[relative]=dict(size=path.stat().st_size,sha256=digest(path))
    (campaign/'analysis-files.json').write_text(json.dumps(dict(schema_version=1,
        producing_commit='a'*40,postprocessing_commit='b'*40,files=files)))
    return campaign


class ReportViews(unittest.TestCase):
    def fixture(self,root):
        import json
        from pack import pack_campaign
        campaign=actual_tool_campaign(root);packet=root/'packet';pack_campaign(campaign,packet)
        return campaign,packet,json.loads((packet/'index.json').read_text())
    def test_full_and_projected_members_preserve_report_semantics(self):
        from pack import extract_packet,extract_analysis
        from packet_io import verify_report_view
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);campaign,packet,index=self.fixture(root)
            extract_analysis(packet,root/'bootstrap')
            extract_packet(packet,root/'full');extract_packet(packet,root/'view',report_view=True)
            manifest=verify_report_view(root/'view');name='cells/fixture-facility--native.toml'
            self.assertEqual(read_cell_record(root/'full'/name),read_cell_record(root/'view'/name))
            self.assertNotIn(b'ignored=',(root/'view'/name).read_bytes())
            self.assertEqual((campaign/name).read_bytes(),(root/'full'/name).read_bytes())
            self.assertEqual((root/'view/extraction-index.json').read_bytes(),(packet/'index.json').read_bytes())
            for filename,entry in manifest['files'].items():
                self.assertEqual(entry['original_sha256'],index['files'][filename]['sha256'])
                if not entry['projected']:self.assertEqual(entry['view_sha256'],entry['original_sha256'])
    def test_missing_changed_and_extra_view_files_are_rejected(self):
        from pack import extract_packet
        from packet_io import verify_report_view
        for mutation in ('cell','manifest','index','extra','revision'):
            with self.subTest(mutation=mutation),tempfile.TemporaryDirectory() as temp:
                import json
                root=Path(temp);_,packet,_=self.fixture(root);view=root/'view'
                extract_packet(packet,view,report_view=True)
                if mutation=='cell':(view/'cells/fixture-facility--native.toml').write_bytes(b'status="changed"\n')
                elif mutation=='manifest':(view/'extraction-view.json').unlink()
                elif mutation=='index':(view/'extraction-index.json').write_bytes(b'{}')
                elif mutation=='extra':(view/'unindexed-file').write_bytes(b'x')
                else:
                    path=view/'extraction-view.json';record=json.loads(path.read_text())
                    record['postprocessing_commit']='c'*40;path.write_text(json.dumps(record))
                with self.assertRaises(ValueError):verify_report_view(view)
    def test_changed_omitted_metadata_is_still_hashed(self):
        import json
        from pack import pack_campaign,extract_packet
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);campaign,_,original=self.fixture(root)
            path=campaign/'cells/fixture-facility--native.toml';path.write_text(path.read_text().replace('"123"','"456"'))
            second=root/'changed-packet';pack_campaign(campaign,second)
            index=json.loads((second/'index.json').read_text());index['files']=original['files']
            (second/'index.json').write_text(json.dumps(index))
            with self.assertRaisesRegex(ValueError,'Member hash'):extract_packet(second,root/'view',report_view=True)
            with self.assertRaisesRegex(ValueError,'Incomplete'):
                from packet_io import verify_report_view
                verify_report_view(root/'view')
    def test_view_byte_limit_stops_writing_before_acceptance(self):
        from unittest.mock import patch
        from pack import extract_packet
        from packet_io import verify_report_view
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);_,packet,_=self.fixture(root)
            with patch('packet_io.MAX_REPORT_VIEW',1000):
                with self.assertRaisesRegex(ValueError,'allowance'):extract_packet(packet,root/'view',report_view=True)
            with self.assertRaisesRegex(ValueError,'Incomplete'):verify_report_view(root/'view')
    def test_reordered_and_truncated_logical_streams_are_rejected(self):
        import hashlib,json
        from packet_io import write_archive,extract_v2
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);source=root/'source';source.mkdir();packet=root/'packet';packet.mkdir()
            (source/'value').write_bytes(bytes(range(256))*32)
            archive=write_archive(source,[Path('value')],packet,'test.tar.xz',1024**2,part_limit=80)
            index=dict(files={'value':dict(size=(source/'value').stat().st_size,sha256=digest(source/'value'))},
                archives={'test.tar.xz':archive},compressed_bytes=archive['size'],
                uncompressed_bytes=(source/'value').stat().st_size)
            archive['parts'].reverse()
            with self.assertRaises(ValueError):extract_v2(packet,root/'reordered',index)
            archive['parts'].reverse();last=archive['parts'][-1];path=packet/last['name']
            path.write_bytes(path.read_bytes()[:-10]);last.update(size=path.stat().st_size,sha256=digest(path))
            content=b''.join((packet/p['name']).read_bytes() for p in archive['parts'])
            archive.update(size=len(content),sha256=hashlib.sha256(content).hexdigest());index['compressed_bytes']=len(content)
            with self.assertRaisesRegex(ValueError,'Truncated'):extract_v2(packet,root/'truncated',index)


    def test_self_consistent_view_revision_cannot_replace_retained_identity(self):
        import hashlib,json
        from pack import extract_packet
        from packet_io import verify_report_view
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);_,packet,_=self.fixture(root);view=root/'view'
            extract_packet(packet,view,report_view=True)
            path=view/'extraction-index.json';index=json.loads(path.read_text())
            index['postprocessing_commit']='c'*40;path.write_text(json.dumps(index))
            checksum=digest(path);(view/'.report-view').write_text(checksum+'\n')
            path=view/'extraction-view.json';manifest=json.loads(path.read_text())
            manifest.update(postprocessing_commit='c'*40,packet_index_sha256=checksum)
            path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError,'source revisions'):verify_report_view(view)

    def test_history_retains_its_own_declared_inventory(self):
        import json,shutil
        from freeze_analysis import verify_analysis
        from campaign import STUDY
        with tempfile.TemporaryDirectory() as temp:
            campaign=actual_tool_campaign(Path(temp));history=campaign/'analysis-history'/('b'*40)
            history.mkdir(parents=True)
            shutil.copytree(campaign/'analysis-source',history/'analysis-source')
            for name in ('analysis-files.json','run.toml'):shutil.copy2(campaign/name,history/name)
            current=campaign/'analysis-files.json';record=json.loads(current.read_text())
            record['postprocessing_commit']='c'*40
            relative=str(STUDY/'new-helper.py');path=campaign/'analysis-source'/relative
            path.write_bytes(b'# next generation helper\n')
            record['files'][relative]=dict(size=path.stat().st_size,sha256=digest(path))
            current.write_text(json.dumps(record));self.assertEqual(verify_analysis(campaign)['postprocessing_commit'],'c'*40)
            old=history/'analysis-source'/STUDY/'report.py';old.write_bytes(old.read_bytes()+b'\n# altered history\n')
            with self.assertRaisesRegex(ValueError,'source bytes'):verify_analysis(campaign)

    def test_removed_view_indicators_cannot_disable_required_integrity(self):
        from pack import extract_packet
        from packet_io import verify_report_view,VIEW_RESERVED
        for delete_all in (False,True):
            with self.subTest(delete_all=delete_all),tempfile.TemporaryDirectory() as temp:
                root=Path(temp);_,packet,_=self.fixture(root);view=root/'view'
                extract_packet(packet,view,report_view=True)
                names=VIEW_RESERVED if delete_all else {'.report-view','extraction-view.json'}
                for name in names:(view/name).unlink()
                with self.assertRaises(ValueError):verify_report_view(view,required=delete_all)

    def test_derived_view_cannot_be_repacked_as_original_raw_observations(self):
        from pack import pack_campaign,extract_packet
        from packet_io import VIEW_RESERVED
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);_,packet,_=self.fixture(root);view=root/'view'
            extract_packet(packet,view,report_view=True)
            with self.assertRaisesRegex(ValueError,'derived report view'):
                pack_campaign(view,root/'repacked')
            self.assertFalse((root/'repacked').exists())
            for indicator in VIEW_RESERVED:
                raw=root/indicator.replace('.','_');raw.mkdir();(raw/indicator).write_bytes(b'')
                with self.assertRaisesRegex(ValueError,'derived report view'):
                    pack_campaign(raw,root/'repacked')
                self.assertFalse((root/'repacked').exists())


if __name__=='__main__':unittest.main()
