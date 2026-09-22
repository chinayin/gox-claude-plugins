#!/usr/bin/env python3
"""Build a standalone Codex marketplace; never edit the shared Claude sources."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

import yaml

ROOT = Path(__file__).resolve().parent.parent
SKILLS = ('engineering', 'go', 'shell', 'skill')


def build(output):
    if output.exists() or output.is_symlink():
        raise ValueError(f'output already exists: {output}; choose a fresh --output directory')
    for directory in ('plugins', '.claude-plugin', 'templates', 'codex/plugins'):
        if output.resolve().is_relative_to((ROOT / directory).resolve()):
            raise ValueError(f'output must not be inside source directory: {directory}')
    files = {}
    sources = {}

    def add(source, target):
        if source.is_symlink():
            raise ValueError(f'symlink is not allowed in a package: {source}')
        data = source.read_bytes()
        files[target] = data
        sources[str(source.relative_to(ROOT))] = hashlib.sha256(data).hexdigest()

    def tree(source, target):
        if source.is_symlink():
            raise ValueError(f'symlink is not allowed in a package: {source}')
        if not source.is_dir():
            raise ValueError(f'missing directory: {source}')
        for path in sorted(source.rglob('*')):
            if path.is_symlink():
                raise ValueError(f'symlink is not allowed in a package: {path}')
            if path.is_file():
                add(path, target / path.relative_to(source))

    for name in ('gox-code-rules', 'gox-guard'):
        target = Path('plugins') / name
        tree(ROOT / 'codex/plugins' / name, target)
        add(ROOT / 'LICENSE', target / 'LICENSE')

    for name in SKILLS:
        source = ROOT / 'plugins/gox-code-rules/skills' / name
        tree(source, Path('plugins/gox-code-rules/skills') / name)
        skill = source / 'SKILL.md'
        lines = skill.read_text(encoding='utf-8').splitlines()
        try:
            if lines[0] != '---':
                raise ValueError('missing frontmatter')
            meta = yaml.safe_load('\n'.join(lines[1:lines.index('---', 1)]))
            if not isinstance(meta, dict) or meta.get('name') != name:
                raise ValueError('skill name must match its directory')
            if not isinstance(meta.get('description'), str) or not meta['description'].strip():
                raise ValueError('description must be a non-empty string')
        except (IndexError, ValueError, yaml.YAMLError) as exc:
            raise ValueError(f'{skill}: {exc}') from exc
        for doc in source.rglob('*.md'):
            for ref in re.findall(r'references/[A-Za-z0-9._-]+\.md', doc.read_text(encoding='utf-8')):
                if not (source / ref).is_file():
                    raise ValueError(f'{doc}: missing reference {ref}')

    add(ROOT / 'plugins/gox-guard/hooks/secrets.sh', Path('plugins/gox-guard/hooks/secrets.sh'))
    add(ROOT / 'codex/marketplace.json', Path('.agents/plugins/marketplace.json'))
    revision = subprocess.run(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'],
                              capture_output=True, text=True)
    files[Path('BUILD.json')] = (json.dumps({
        'sourceRevision': revision.stdout.strip() if revision.returncode == 0 else None,
        'sourceHashes': sources,
    }, indent=2, sort_keys=True) + '\n').encode()
    # All inputs are validated before creating any output. Existing directories are never removed.
    output.mkdir(parents=True, exist_ok=False)
    for path, data in sorted(files.items()):
        target = output / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'codex/dist',
                        help='fresh output directory (default: codex/dist)')
    args = parser.parse_args()
    try:
        result = build(args.output.absolute())
    except (OSError, ValueError) as exc:
        print(f'Error: {exc}', file=sys.stderr)
        return 1
    print(result)
    return 0


if __name__ == '__main__':
    sys.exit(main())
