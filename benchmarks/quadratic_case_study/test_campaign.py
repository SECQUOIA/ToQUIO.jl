import io
import json
import tarfile
import tempfile
import unittest
from pathlib import Path
from campaign import extract_checked, planned_ids, write_flat_toml, read_toml
from report import feasible, source_objective

class ArtifactContracts(unittest.TestCase):
    def test_archive_refuses_traversal_links_duplicates_and_size(self):
        for names, allowance in [(['../escape'],100),(['a','a'],100),(['a'],0)]:
            with self.subTest(names=names,allowance=allowance), tempfile.TemporaryDirectory() as temp:
                root=Path(temp);archive=root/'test.tar.gz'
                with tarfile.open(archive,'w:gz') as target:
                    for name in names:
                        entry=tarfile.TarInfo(name);entry.size=1
                        target.addfile(entry,io.BytesIO(b'x'))
                with self.assertRaises(ValueError):extract_checked(archive,root/'out',allowance=allowance)
                self.assertFalse((root/'escape').exists())
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);archive=root/'test.tar.gz'
            with tarfile.open(archive,'w:gz') as target:
                item=tarfile.TarInfo('link');item.type=tarfile.SYMTYPE;item.linkname='/tmp/other'
                target.addfile(item)
            with self.assertRaises(ValueError):extract_checked(archive,root/'out')
    def test_archive_roundtrip_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);archive=root/'test.tar.gz'
            with tarfile.open(archive,'w:gz') as target:
                entry=tarfile.TarInfo('family/input.toml');entry.size=3
                target.addfile(entry,io.BytesIO(b'abc'))
            extract_checked(archive,root/'out')
            self.assertEqual((root/'out/family/input.toml').read_bytes(),b'abc')
            with self.assertRaises(ValueError):extract_checked(archive,root/'out')
    def test_scalar_records_do_not_execute_quoted_values(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'record.toml'
            record=dict(identity='literal "$()" `command` \\ and newline\n',flag=True,number=3)
            write_flat_toml(path,record);self.assertEqual(read_toml(path),record)
    def test_original_source_audit(self):
        source=dict(lower=[0,0],upper=[2,2],linear=[0,0],quadratic_rows=[[2,1],[1,3]],
                    rows=[[[1,1],[2,2]]],relations=['le'],rhs=[3])
        self.assertTrue(feasible(source,[1,1]));self.assertEqual(source_objective(source,[1,1]),7)
        for invalid in ([2,2],[1.5,0],[-1,0],[0]):self.assertFalse(feasible(source,invalid))
    def test_plan_keeps_all_arms_and_baselines(self):
        records=[dict(instance_id='a',direct=True,sha256='first'),dict(instance_id='b',direct=False,sha256='second')]
        planned=planned_ids(records,['native','binary'])
        self.assertEqual(len(planned),5);self.assertEqual(planned['a--direct']['source_hash'],'first')
        self.assertNotIn('b--direct',planned)


class IncompleteCampaignReporting(unittest.TestCase):
    def packet(self,root):
        from campaign import digest
        source=root/'source';profile=source/'benchmarks/quadratic_case_study'
        (profile/'inputs').mkdir(parents=True);(root/'inputs').mkdir()
        (profile/'protocol.toml').write_text('status = "frozen"\narms = ["native","radix4","bounded4-cap64","binary-radix2","toqubo-controlled-binary","toqubo-default-binary"]\n')
        concrete='''id="case"
family="knapsack"
lower=[0]
upper=[2]
linear=[0.0]
quadratic_rows=[[1.0]]
rows=[[[1,1]]]
relations=["le"]
rhs=[1]
'''
        (root/'inputs/case.toml').write_text(concrete)
        checksum=digest(root/'inputs/case.toml')
        (root/'inputs/inventory.toml').write_text('''[[instances]]
instance_id="case"
family="knapsack"
profile="rounded-fidelity"
n=1
m=2
replicate=1
direct=true
file="case.toml"
sha256="'''+checksum+'"\n')
        index=dict(files={p.name:digest(p) for p in (root/'inputs').iterdir()},archives={})
        (profile/'inputs/index.json').write_text(json.dumps(index))
        hashes={str(p.relative_to(source)):digest(p) for p in source.rglob('*') if p.is_file()}
        (root/'source-files.json').write_text(json.dumps(hashes))
        write_flat_toml(root/'run.toml',dict(source_commit='f'*40,
            protocol_sha256=digest(profile/'protocol.toml'),backend='SCIP'))
        from campaign import planned_ids
        from report import ARMS
        plan=planned_ids(read_toml(root/'inputs/inventory.toml')['instances'],ARMS)
        (root/'plan.json').write_text(json.dumps(plan));(root/'cells').mkdir();(root/'chains').mkdir()
        return plan
    def test_unstarted_batches_remain_missing_not_failures(self):
        from report import aggregate
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);self.packet(root)
            summary,_,_,batches=aggregate(root,root/'report',allow_incomplete=True)
            self.assertEqual(len(batches),18)
            self.assertTrue(all(r['completed_reads']==0 and r['missing_or_unaudited_reads']==10 for r in batches))
            self.assertTrue(all(r['terminal_feasible_frequency'] is None for r in batches))
            self.assertFalse(summary['full_execution'])
    def test_extracted_input_cannot_be_replaced_with_self_consistent_plan(self):
        from report import verify
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);self.packet(root)
            path=root/'inputs/case.toml';path.write_text(path.read_text().replace('rhs=[1]','rhs=[2]'))
            with self.assertRaisesRegex(ValueError,'committed inventory'):verify(root,allow_incomplete=True)

if __name__=='__main__':unittest.main()
