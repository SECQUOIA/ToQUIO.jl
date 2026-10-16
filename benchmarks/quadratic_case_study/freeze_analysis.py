"""Freeze reporting tools separately from the immutable measurement source."""
import argparse, json, subprocess
from pathlib import Path
from campaign import STUDY, digest, read_toml

TOOLS = ('report.py', 'analysis.py', 'plots.py', 'campaign.py', 'compare.py', 'pack.py',
         'packet_io.py', 'freeze_analysis.py', 'resource_conformance.py', 'supervision_conformance.py',
         'packaging_conformance.py',
         'plot-requirements.txt', 'plot-lock.txt')


def verify_snapshot(root):
    record = json.loads((root/'analysis-files.json').read_text())
    if record['producing_commit'] != read_toml(root/'run.toml')['source_commit']:
        raise ValueError('Postprocessing producer identity mismatch')
    expected = set(record['files'])
    # Historical declared closures need not grow when a later freeze adds a helper.
    required = {str(STUDY/name) for name in ('report.py','analysis.py','plots.py','pack.py','freeze_analysis.py')}
    if (record.get('schema_version')!=1 or not required.issubset(expected) or
            any(Path(name).parent!=STUDY for name in expected)):
        raise ValueError('Unexpected postprocessing source inventory')
    tree = root/'analysis-source'; paths = list(tree.rglob('*'))
    if tree.is_symlink() or any(p.is_symlink() for p in paths):
        raise ValueError('Unexpected postprocessing source link')
    actual = {str(p.relative_to(tree)) for p in paths if p.is_file()}
    if actual != expected: raise ValueError('Changed postprocessing file inventory')
    for name, entry in record['files'].items():
        path = root/'analysis-source'/name
        if path.is_symlink() or path.stat().st_size != entry['size'] or digest(path) != entry['sha256']:
            raise ValueError('Changed postprocessing source bytes')
    return record


def verify_analysis(root):
    record = verify_snapshot(root)
    for history in (root/'analysis-history').glob('*'):
        if not history.is_dir() or history.is_symlink():
            raise ValueError('Unexpected postprocessing history entry')
        previous = verify_snapshot(history)
        if (history.name!=previous['postprocessing_commit'] or
                previous['producing_commit']!=record['producing_commit']):
            raise ValueError('Changed postprocessing history identity')
    return record


def freeze(source, root):
    source = source.resolve(); root = root.resolve()
    if subprocess.check_output(['git', '-C', str(source), 'status', '--porcelain'], text=True):
        raise ValueError('Postprocessing source must be clean and committed')
    if (root/'analysis-files.json').exists() or (root/'analysis-source').exists():
        raise ValueError('Refuse existing frozen postprocessing source')
    sha = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    files = {}
    for name in TOOLS:
        relative = str(STUDY/name)
        content = subprocess.check_output(['git', '-C', str(source), 'show', sha+':'+relative])
        path = root/'analysis-source'/relative; path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content); files[relative] = dict(size=len(content), sha256=digest(path))
    record = dict(schema_version=1, producing_commit=read_toml(root/'run.toml')['source_commit'],
                  postprocessing_commit=sha, files=files)
    (root/'analysis-files.json').write_text(json.dumps(record, sort_keys=True, indent=2)+'\n')
    verify_analysis(root)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path); parser.add_argument('campaign', type=Path)
    args = parser.parse_args(); freeze(args.source, args.campaign)
