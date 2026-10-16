import csv
import io
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from resource_conformance import digest
from supervision_conformance import attach
import test_resource_conformance as resource_tests


def add_recovery(root, active_cell='overlap--native', second_cell='after--native'):
    process=root/'processes';process.mkdir(exist_ok=True)
    container='manufactured-validation-worker';identity='a'*64
    (process/'0001.json').write_text(json.dumps(dict(container=container)))
    controllers=[]
    for version in (1,2):
        name=f'processes/adopt-campaign-supervisor-v{version}.py'
        (root/name).write_text(f'# Manufactured validation controller {version}\n')
        controllers.append(dict(file=name,sha256=digest(root/name)))
    common=dict(schema_version=1,source_commit='f'*40,original_container=container,
                original_container_id=identity,worker_restarted=False,measurement_reruns=False,
                measurement_source_changed=False,statistical_protocol_changed=False)
    first=dict(common,kind='interrupted-host-supervisor-recovery',
               last_confirmed_supervision_utc_approx='2026-10-15 10:30 UTC',
               conservative_gap_start_utc='2026-10-15T10:29:00+00:00',
               supervision_restored_utc='2026-10-15T10:31:00+00:00',
               active_cell=active_cell,active_phase_utc='2026-10-15T10:30:00')
    first_name='processes/supervisor-recovery-fixture.json'
    (root/first_name).write_text(json.dumps(first))
    second=dict(common,kind='controlled-supervisor-handoff',
                last_confirmed_supervision_utc_approx='2026-10-15T11:51:00+00:00',
                conservative_gap_start_utc='2026-10-15T11:51:00+00:00',
                supervision_restored_utc='2026-10-15T11:52:00+00:00',
                active_cell=second_cell,active_phase_utc='2026-10-15T11:51:00',
                prior_recovery_record=first_name,prior_recovery_sha256=digest(root/first_name),
                prior_controller_source=controllers[0]['file'],prior_controller_sha256=controllers[0]['sha256'],
                controller_source=controllers[1]['file'],controller_sha256=controllers[1]['sha256'])
    second_name='processes/supervisor-handoff-fixture.json'
    (root/second_name).write_text(json.dumps(second))
    entries=[dict(file=name,sha256=digest(root/name),controller_source_file=controller['file'],
                  controller_source_sha256=controller['sha256']) for name,controller in
                 zip((first_name,second_name),controllers)]
    manifest=dict(schema_version=1,source_commit='f'*40,original_container=container,
                  original_container_id=identity,recoveries=entries,controllers=controllers,
                  window_basis='Manufactured validation gaps; closed union, first minute conservatively padded')
    (process/'supervisor-conformance.json').write_text(json.dumps(manifest))
    return manifest


class SupervisionConformance(unittest.TestCase):
    def fixture(self,root):
        resource_tests.ResourceConformance().fixture(root)
        # A cell wholly between the two gaps must not be marked as overlapping.
        identifier='between--native'
        plan=json.loads((root/'plan.json').read_text());plan[identifier]=dict(kind='structural')
        (root/'plan.json').write_text(json.dumps(plan))
        (root/'attempts'/(identifier+'.toml')).write_text(
            f'cell_id="{identifier}"\nstarted_utc="2026-10-15T10:32:00"\n')
        (root/'cells'/(identifier+'.toml')).write_text(
            f'cell_id="{identifier}"\nfinished_utc="2026-10-15T11:49:00"\nstatus="measured"\n')
        return add_recovery(root)

    def test_separate_gap_union_parent_chains_original_bytes_and_view_parity(self):
        from report import projected_cell_bytes,bounded_cell_lines
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);campaign=root/'campaign';self.fixture(campaign)
            before={str(p.relative_to(campaign)):digest(p) for p in campaign.rglob('*') if p.is_file()}
            summary=attach(campaign,root/'report')
            self.assertEqual((summary['overlapping_cells'],summary['overlapping_chains']),(2,2))
            self.assertEqual(len(summary['uncertainty_windows']),2)
            table=root/'report/supervision-conformance/supervision-conformance-cells.csv'
            with table.open() as stream:rows={r['cell_id']:r for r in csv.DictReader(stream)}
            self.assertEqual(rows['between--native']['potential_overlap'],'false')
            self.assertEqual(rows['overlap--native']['raw_status'],'measured')
            self.assertEqual(rows['overlap--native']['supervision_qualification'],
                             'continuous-watchdog-enforcement-uncertain')
            self.assertNotIn('resource_qualification',rows['overlap--native'])
            view=root/'view';shutil.copytree(campaign,view)
            for path in (view/'cells').glob('*.toml'):
                path.write_bytes(b''.join(projected_cell_bytes(bounded_cell_lines(io.BytesIO(path.read_bytes())))))
            self.assertEqual(attach(view,root/'view-report'),summary)
            self.assertEqual(attach(campaign,root/'report'),summary)
            for path in (root/'report/supervision-conformance').iterdir():
                self.assertEqual(path.read_bytes(),(root/'view-report/supervision-conformance'/path.name).read_bytes())
            self.assertEqual(before,{str(p.relative_to(campaign)):digest(p) for p in campaign.rglob('*') if p.is_file()})

    def test_invalid_or_unbound_recovery_fails_before_replacing_own_reports(self):
        for mutation in ('missing-manifest','controller-bytes','recovery-bytes','extra-recovery',
                         'source','shortened-window','rerun','handoff-chain','active-cell','future-phase'):
            with self.subTest(mutation=mutation),tempfile.TemporaryDirectory() as temp:
                root=Path(temp);campaign=root/'campaign';manifest=self.fixture(campaign)
                report=root/'report';attach(campaign,report)
                before={p.name:p.read_bytes() for p in (report/'supervision-conformance').iterdir()}
                path=campaign/'processes/supervisor-conformance.json'
                if mutation=='missing-manifest':path.unlink()
                elif mutation=='controller-bytes':(campaign/manifest['controllers'][0]['file']).write_text('changed')
                elif mutation=='extra-recovery':(campaign/'processes/supervisor-recovery-extra.json').write_text('{}')
                elif mutation=='source':manifest['source_commit']='e'*40
                else:
                    entry=manifest['recoveries'][1];event_path=campaign/entry['file']
                    event=json.loads(event_path.read_text())
                    if mutation=='shortened-window':event['conservative_gap_start_utc']='2026-10-15T11:51:01+00:00'
                    elif mutation=='rerun':event['measurement_reruns']=True
                    elif mutation=='handoff-chain':event['prior_recovery_sha256']='0'*64
                    elif mutation=='active-cell':event['active_cell']='between--native'
                    elif mutation=='future-phase':event['active_phase_utc']='2026-10-15T12:00:00'
                    event_path.write_text(json.dumps(event)+'\n')
                    if mutation!='recovery-bytes':entry['sha256']=digest(event_path)
                if mutation!='missing-manifest':path.write_text(json.dumps(manifest))
                with self.assertRaises(ValueError):attach(campaign,report)
                self.assertEqual(before,{p.name:p.read_bytes() for p in (report/'supervision-conformance').iterdir()})

    def test_report_exposes_both_qualifications_and_compare_checks_supervision(self):
        from test_campaign import IncompleteCampaignReporting
        from report import aggregate
        from analysis import render
        from compare import compare
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);IncompleteCampaignReporting().packet(root)
            resource_tests.ResourceConformance().incident(root,'case--native')
            (root/'attempts').mkdir()
            (root/'attempts/case--native.toml').write_text('cell_id="case--native"\nstarted_utc="2026-10-15T10:20:00"\n')
            add_recovery(root,'case--native','case--native')
            summary,*_=aggregate(root,root/'report',allow_incomplete=True);render(root/'report')
            self.assertIn('resource_conformance',summary);self.assertIn('supervision_conformance',summary)
            text=(root/'report/REPORT.md').read_text()
            self.assertIn('Resource conformance is qualified',text)
            self.assertIn('Deadline conformance is qualified',text)
            self.assertIn('does not retrospectively establish watchdog coverage',text)
            shutil.copytree(root/'report',root/'rebuilt')
            compare(root/'report',root/'rebuilt',require_complete=False)
            table=root/'rebuilt/supervision-conformance/supervision-conformance-cells.csv'
            table.write_text(table.read_text().replace('not-yet-measured','incorrectly-cleared',1))
            with self.assertRaisesRegex(ValueError,'supervision-conformance-cells'):
                compare(root/'report',root/'rebuilt',require_complete=False)


if __name__=='__main__':unittest.main()
