import csv
import io
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from resource_conformance import attach, digest, qualification, utc


class ResourceConformance(unittest.TestCase):
    start = '2026-10-15T10:29:00+00:00'
    end = '2026-10-15T11:46:47.385764+00:00'

    def incident(self, root, active_cell='overlap--native'):
        process = root/'processes'
        process.mkdir(exist_ok=True)
        name = 'processes/resource-control-observation-fixture.json'
        source = 'f'*40
        (root/name).write_text(json.dumps(dict(source_commit=source, fixture=True,
            active_cell=active_cell, recorded_at_utc=self.end,
            prior_observation=dict(utc_approx='2026-10-15 10:30 UTC',memory_swap_max='0'),
            kernel_after=dict(memory_swap_max='0'))))
        record = dict(schema_version=1, source_commit=source, incident_file=name,
                      incident_sha256=digest(root/name), window_start_utc=self.start,
                      window_end_utc=self.end, window_basis='Manufactured validation interval')
        (process/'resource-control-window.json').write_text(json.dumps(record))
        return record

    def fixture(self, root):
        root.mkdir()
        (root/'run.toml').write_text('source_commit="'+'f'*40+'"\n')
        for name in ('cells','attempts','chains'):
            (root/name).mkdir()
        intervals = dict(before=('10:00:00','10:28:59'),
                         overlap=('10:20:00','11:50:00'), after=('11:47:00','12:00:00'))
        plan = {}
        for name, (start, finish) in intervals.items():
            identifier = name+'--native'
            plan[identifier] = dict(kind='structural')
            (root/'attempts'/(identifier+'.toml')).write_text(
                f'cell_id="{identifier}"\nstarted_utc="2026-10-15T{start}"\n')
            (root/'cells'/(identifier+'.toml')).write_text(
                f'cell_id="{identifier}"\nfinished_utc="2026-10-15T{finish}"\n'
                'status="measured"\n[compiler.metadata]\nunused="retained raw diagnostics"\n')
            (root/'chains'/(identifier+'--b1-r1.toml')).write_bytes(b'unchanged chain fixture\n')
        (root/'plan.json').write_text(json.dumps(plan))
        (root/'completion.json').write_text('{}')
        self.incident(root)

    def test_closed_boundaries_and_missing_intervals_are_conservative(self):
        w0, w1 = utc(self.start), utc(self.end)
        cases = [
            ('2026-10-15T10:00:00','2026-10-15T10:28:59',False),
            ('2026-10-15T11:46:48','2026-10-15T12:00:00',False),
            ('2026-10-15T10:00:00','2026-10-15T10:29:00',True),
            ('2026-10-15T11:46:47.385764','2026-10-15T12:00:00',True),
            ('2026-10-15T10:28:00','2026-10-15T12:00:00',True),
            ('2026-10-15T11:00:00','',True), ('','2026-10-15T11:00:00',True), ('','',True)]
        for start, finish, expected in cases:
            with self.subTest(start=start, finish=finish):
                self.assertIs(qualification(start,finish,w0,w1,terminal=True)[0],expected)
        self.assertIsNone(qualification('','',w0,w1,terminal=False)[0])
        with self.assertRaisesRegex(ValueError,'Reversed'):
            qualification('2026-10-15T12:00:00','2026-10-15T11:00:00',w0,w1,terminal=True)

    def test_parent_interval_associations_preserve_raw_values_and_view_parity(self):
        from report import projected_cell_bytes, bounded_cell_lines
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);campaign=root/'campaign';self.fixture(campaign)
            original={str(p.relative_to(campaign)):digest(p) for p in campaign.rglob('*') if p.is_file()}
            summary=attach(campaign,root/'full-report')
            self.assertEqual((summary['overlapping_cells'],summary['overlapping_chains']),(1,1))
            self.assertTrue(summary['campaign_terminal']);self.assertFalse(summary['measurement_values_changed'])
            with (root/'full-report/resource-conformance/resource-conformance-cells.csv').open() as stream:
                rows={r['cell_id']:r for r in csv.DictReader(stream)}
            self.assertEqual(rows['overlap--native']['raw_status'],'measured')
            self.assertEqual(rows['after--native']['potential_overlap'],'false')
            self.assertEqual(rows['overlap--native']['potential_overlap'],'true')
            # Existing destinations support deterministic regeneration.
            self.assertEqual(attach(campaign,root/'full-report'),summary)
            view=root/'view';shutil.copytree(campaign,view)
            for path in (view/'cells').glob('*.toml'):
                projected=b''.join(projected_cell_bytes(bounded_cell_lines(io.BytesIO(path.read_bytes()))))
                path.write_bytes(projected)
            self.assertEqual(attach(view,root/'view-report'),summary)
            for path in (root/'full-report/resource-conformance').iterdir():
                self.assertEqual(path.read_bytes(),(root/'view-report/resource-conformance'/path.name).read_bytes())
            self.assertEqual(original,{str(p.relative_to(campaign)):digest(p) for p in campaign.rglob('*') if p.is_file()})

    def test_missing_window_changed_incident_extra_incident_and_wrong_source_fail(self):
        for mutation in ('missing-window','incident-bytes','extra-incident','source'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temp:
                root=Path(temp);campaign=root/'campaign';self.fixture(campaign)
                process=campaign/'processes';window=process/'resource-control-window.json'
                if mutation=='missing-window':window.unlink()
                elif mutation=='incident-bytes':
                    (process/'resource-control-observation-fixture.json').write_text('{}')
                elif mutation=='extra-incident':(process/'resource-control-observation-extra.json').write_text('{}')
                else:
                    record=json.loads(window.read_text());record['source_commit']='a'*40
                    window.write_text(json.dumps(record))
                with self.assertRaises(ValueError):attach(campaign,root/'report')

    def test_report_exposes_qualification_and_compare_checks_additive_tables(self):
        from test_campaign import IncompleteCampaignReporting
        from report import aggregate
        from analysis import render
        from compare import compare
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);IncompleteCampaignReporting().packet(root);self.incident(root,'case--native')
            (root/'attempts').mkdir()
            (root/'attempts/case--native.toml').write_text(
                'cell_id="case--native"\nstarted_utc="2026-10-15T11:00:00"\n')
            summary,*_=aggregate(root,root/'report',allow_incomplete=True);render(root/'report')
            self.assertEqual(aggregate(root,root/'report',allow_incomplete=True)[0],summary)
            self.assertIn('resource_conformance',summary)
            text=(root/'report/REPORT.md').read_text()
            self.assertIn('Measurement completion does not certify',text)
            self.assertIn('Resource conformance is qualified',text)
            shutil.copytree(root/'report',root/'rebuilt')
            compare(root/'report',root/'rebuilt',require_complete=False)
            table=root/'rebuilt/resource-conformance/resource-conformance-cells.csv'
            table.write_text(table.read_text().replace('not-yet-measured','incorrectly-cleared',1))
            with self.assertRaisesRegex(ValueError,'resource-conformance-cells'):
                compare(root/'report',root/'rebuilt',require_complete=False)

    def test_shortened_unrelated_or_unsupported_windows_fail_before_replacing_reports(self):
        for mutation in ('end','start','basis','active'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temp:
                root=Path(temp);campaign=root/'campaign';self.fixture(campaign)
                report=root/'report';attach(campaign,report)
                before={p.name:p.read_bytes() for p in (report/'resource-conformance').iterdir()}
                path=campaign/'processes/resource-control-window.json';record=json.loads(path.read_text())
                if mutation=='end':record['window_end_utc']='2026-10-15T11:00:00+00:00'
                elif mutation=='start':record['window_start_utc']='2026-10-15T11:00:00+00:00'
                elif mutation=='basis':record['window_basis']=' '
                else:
                    incident=campaign/record['incident_file'];data=json.loads(incident.read_text())
                    data['active_cell']='after--native';incident.write_text(json.dumps(data))
                    record['incident_sha256']=digest(incident)
                path.write_text(json.dumps(record))
                with self.assertRaisesRegex(ValueError,'window'):
                    attach(campaign,report)
                self.assertEqual(before,{p.name:p.read_bytes() for p in (report/'resource-conformance').iterdir()})


if __name__=='__main__':unittest.main()
