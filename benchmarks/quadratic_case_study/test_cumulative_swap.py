import json
import tempfile
import tomllib
import unittest
from pathlib import Path
from resource_conformance import attach, digest, SWAP_SEMANTICS
import test_resource_conformance as resource_tests


def add_cumulative_evidence(root):
    """Manufactured observations only, for independently checkable guard cases."""
    process=root/'processes';container='manufactured-validation-worker';identity='a'*64
    ledger=process/'0001.json'
    if ledger.exists():assert json.loads(ledger.read_text())['container']==container
    else:ledger.write_text(json.dumps(dict(container=container)))
    window_path=process/'resource-control-window.json';window=json.loads(window_path.read_text())
    incident=root/window['incident_file'];data=json.loads(incident.read_text())
    data.update(container=container,container_id=identity);incident.write_text(json.dumps(data))
    window['incident_sha256']=digest(incident);window_path.write_text(json.dumps(window))
    started='2026-10-15T06:00:00Z';state=f'{identity} true {started}'
    common=dict(schema_version=1,container=container,exit_code=0,stderr='',fixture=True)
    observations=[
        dict(common,observation_started_utc='2026-10-15T12:00:00+00:00',
             observation_finished_utc='2026-10-15T12:00:01+00:00',identity_and_state=state,
             stdout='memory.swap.peak\n0\nmemory.swap.events\nhigh 0\nmax 0\nfail 0\n'),
        dict(common,observation_started_utc='2026-10-15T12:00:02+00:00',
             observation_finished_utc='2026-10-15T12:00:03+00:00',
             stdout='kernel_release\n6.6.0-validation\nswap_peak_mode\n444\nfresh_read_only_swap_peak\n0\n'),
        dict(common,observation_started_utc='2026-10-15T12:00:04+00:00',
             observation_finished_utc='2026-10-15T12:00:05+00:00',stdout=state+'\n')]
    names=['processes/cumulative-swap-observation-fixture.json',
           'processes/swap-counter-semantics-observation-fixture.json',
           'processes/cumulative-swap-container-identity-fixture.json']
    record=dict(schema_version=1,source_commit=tomllib.loads((root/'run.toml').read_text())['source_commit'],
                container=container,container_id=identity,container_started_utc=started,
                counter_semantics_url=SWAP_SEMANTICS)
    for role,name,observation in zip(('observation','semantics','identity'),names,observations):
        (root/name).write_text(json.dumps(observation))
        record[role+'_file']=name;record[role+'_sha256']=digest(root/name)
    (process/'cumulative-swap-evidence.json').write_text(json.dumps(record))
    return record


class CumulativeSwapEvidence(unittest.TestCase):
    def test_later_readonly_lifetime_witness_narrows_usage_only_through_start(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);campaign=root/'campaign';resource_tests.ResourceConformance().fixture(campaign)
            add_cumulative_evidence(campaign)
            before={str(p.relative_to(campaign)):digest(p) for p in campaign.rglob('*') if p.is_file()}
            summary=attach(campaign,root/'report');usage=summary['cumulative_swap_usage']
            self.assertEqual(usage['recorded_peak_bytes'],0)
            self.assertEqual(usage['through_utc'],'2026-10-15T12:00:00+00:00')
            self.assertFalse(usage['continuous_limit_enforcement_certified'])
            self.assertIn('cannot be certified',summary['conformance'])
            self.assertEqual((summary['overlapping_cells'],summary['overlapping_chains']),(1,1))
            self.assertEqual(before,{str(p.relative_to(campaign)):digest(p) for p in campaign.rglob('*') if p.is_file()})

    def test_unsupported_or_unbound_evidence_fails_before_replacing_reports(self):
        cases=('missing-manifest','missing-window','extra-observation','source','hash','identity',
               'started-at','peak','labels','kernel','mode','early-observation','order','late-creation',
               'independent-identity','exit-code','stderr','semantics-url')
        for mutation in cases:
            with self.subTest(mutation=mutation),tempfile.TemporaryDirectory() as temp:
                root=Path(temp);campaign=root/'campaign';resource_tests.ResourceConformance().fixture(campaign)
                record=add_cumulative_evidence(campaign);report=root/'report';attach(campaign,report)
                before={p.name:p.read_bytes() for p in (report/'resource-conformance').iterdir()}
                manifest=campaign/'processes/cumulative-swap-evidence.json'
                if mutation=='missing-manifest':manifest.unlink()
                elif mutation=='missing-window':(campaign/'processes/resource-control-window.json').unlink()
                elif mutation=='extra-observation':(campaign/'processes/cumulative-swap-observation-extra.json').write_text('{}')
                elif mutation=='source':record['source_commit']='0'*40
                elif mutation=='started-at':record['container_started_utc']='2026-10-15T06:00:01Z'
                elif mutation=='semantics-url':record['counter_semantics_url']='https://invalid.example/'
                else:
                    role='semantics' if mutation in ('kernel','mode') else 'identity' if mutation=='independent-identity' else 'observation'
                    path=campaign/record[role+'_file'];data=json.loads(path.read_text())
                    if mutation=='identity':data['identity_and_state']=data['identity_and_state'].replace(' true ',' false ')
                    elif mutation=='peak':data['stdout']=data['stdout'].replace('peak\n0','peak\n1',1)
                    elif mutation=='labels':data['stdout']=data['stdout'].replace('swap.peak','swap.current')
                    elif mutation=='kernel':data['stdout']=data['stdout'].replace('6.6.0','7.0.0')
                    elif mutation=='mode':data['stdout']=data['stdout'].replace('444','644')
                    elif mutation=='early-observation':data['observation_started_utc']='2026-10-15T11:00:00+00:00'
                    elif mutation=='order':data['observation_finished_utc']='2026-10-15T12:00:04+00:00'
                    elif mutation=='late-creation':
                        record['container_started_utc']='2026-10-15T11:00:00Z'
                        data['identity_and_state']=data['identity_and_state'].replace('06:00:00','11:00:00')
                        identity_path=campaign/record['identity_file'];identity=json.loads(identity_path.read_text())
                        identity['stdout']=identity['stdout'].replace('06:00:00','11:00:00');identity_path.write_text(json.dumps(identity))
                        record['identity_sha256']=digest(identity_path)
                    elif mutation=='independent-identity':data['stdout']=data['stdout'].replace(' true ',' false ')
                    elif mutation=='exit-code':data['exit_code']=1
                    elif mutation=='stderr':data['stderr']='unexpected diagnostic'
                    path.write_text(json.dumps(data)+'\n')
                    if mutation!='hash':record[role+'_sha256']=digest(path)
                if mutation!='missing-manifest':manifest.write_text(json.dumps(record))
                with self.assertRaises(ValueError):attach(campaign,report)
                self.assertEqual(before,{p.name:p.read_bytes() for p in (report/'resource-conformance').iterdir()})

    def test_report_retains_enforcement_qualification_and_bounds_later_usage_claim(self):
        from test_campaign import IncompleteCampaignReporting
        from report import aggregate
        from analysis import render
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);IncompleteCampaignReporting().packet(root)
            resource_tests.ResourceConformance().incident(root,'case--native')
            (root/'attempts').mkdir();(root/'attempts/case--native.toml').write_text(
                'cell_id="case--native"\nstarted_utc="2026-10-15T10:00:00"\n')
            add_cumulative_evidence(root);aggregate(root,root/'report',allow_incomplete=True);render(root/'report')
            text=(root/'report/REPORT.md').read_text()
            self.assertIn('no recorded cgroup swap usage through `2026-10-15T12:00:00+00:00`',text)
            self.assertNotIn('usage between those observations remains unknown',text)
            self.assertIn('Continuous enforcement of the configured no-swap limit',text)
            self.assertIn('earlier observations remains unverified',text)
            self.assertIn('not host-wide swap activity or the later unfinished campaign',text)


if __name__=='__main__':unittest.main()
