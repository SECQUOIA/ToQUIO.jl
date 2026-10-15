#!/usr/bin/env python3
"""Compare regenerated numerical report bytes with the retained publication."""
import argparse,json
from pathlib import Path

REPORT_FILES=('structural.csv','direct.csv','knapsack-batches.csv','paired-to-native.csv','summary.json','REPORT.md')

def compare(expected,actual,*,require_complete=True):
    summary=json.loads((actual/'summary.json').read_text())
    files=REPORT_FILES
    if 'resource_conformance' in summary:
        files+=tuple('resource-conformance/resource-conformance-'+name for name in
                     ('cells.csv','chains.csv','summary.json'))
    for name in files:
        if (expected/name).read_bytes()!=(actual/name).read_bytes():
            raise ValueError('Regenerated report differs: '+name)
    if require_complete and not summary['full_execution']:raise ValueError('Published software campaign is incomplete')
    print('Verified byte-identical regeneration of all six numerical report files.')
    if 'resource_conformance' in summary:
        print('Verified byte-identical resource-conformance associations and provenance.')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('expected',type=Path)
    parser.add_argument('actual',type=Path);parser.add_argument('--allow-incomplete',action='store_true')
    args=parser.parse_args();compare(args.expected,args.actual,require_complete=not args.allow_incomplete)
