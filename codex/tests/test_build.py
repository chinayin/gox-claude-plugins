"""Exercise the distributable packages, including hooks after relocation."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def snapshot(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob('*') if p.is_file()}


class Packages(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='gox codex ')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root / 'source'
        shutil.copytree(ROOT / 'plugins', self.source / 'plugins')
        shutil.copytree(ROOT / 'codex', self.source / 'codex',
                        ignore=shutil.ignore_patterns('dist', '__pycache__'))
        shutil.copy2(ROOT / 'LICENSE', self.source / 'LICENSE')
        self.output = self.root / 'package'

    def build(self, output=None):
        return subprocess.run(['python3', str(self.source / 'codex/build.py'),
                               '--output', str(output or self.output)],
                              capture_output=True, text=True)

    def built(self):
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stderr)
        return self.output / 'plugins'

    def hook(self, plugin, event, payload=None, extra_env=None):
        root = self.output / 'plugins' / plugin
        config = json.loads((root / 'hooks/hooks.json').read_text())
        command = config['hooks'][event][0]['hooks'][0]['command']
        env = dict(os.environ, PLUGIN_ROOT=str(root))
        env.pop('CLAUDE_PLUGIN_ROOT', None)
        env.pop('GOX_GUARD_SKIP', None)
        env.pop('GOX_GUARD_BIN', None)
        env.update(extra_env or {})
        return subprocess.run(['bash', '-c', command], cwd=self.root,
                              input=json.dumps(payload or {}), text=True,
                              capture_output=True, env=env)

    def test_standalone_packages_preserve_shared_content(self):
        before = snapshot(self.source / 'plugins')
        plugins = self.built()
        self.assertEqual(before, snapshot(self.source / 'plugins'))
        marketplace = json.loads((self.output / '.agents/plugins/marketplace.json').read_text())
        self.assertEqual(marketplace['name'], 'chinayin-codex')
        self.assertEqual([x['name'] for x in marketplace['plugins']], ['gox-code-rules', 'gox-guard'])
        for entry in marketplace['plugins']:
            package = self.output / entry['source']['path']
            manifest = json.loads((package / '.codex-plugin/plugin.json').read_text())
            self.assertEqual(manifest['name'], entry['name'])
            self.assertTrue((package / 'LICENSE').is_file())
            self.assertFalse((package / '.claude-plugin').exists())
        rules = plugins / 'gox-code-rules/skills'
        self.assertEqual(sorted(p.name for p in rules.iterdir()), ['engineering', 'go', 'shell', 'skill'])
        for name in ['engineering', 'go', 'shell', 'skill']:
            self.assertEqual(snapshot(rules / name), snapshot(self.source / 'plugins/gox-code-rules/skills' / name))
        self.assertEqual((plugins / 'gox-guard/hooks/secrets.sh').read_bytes(),
                         (self.source / 'plugins/gox-guard/hooks/secrets.sh').read_bytes())
        self.assertFalse(any(p.is_symlink() for p in self.output.rglob('*')))

    def test_reproducible_build(self):
        self.built()
        second = self.root / 'second'
        self.assertEqual(self.build(second).returncode, 0)
        self.assertEqual(snapshot(self.output), snapshot(second))

    def test_refuses_existing_output_without_modification(self):
        self.output.mkdir()
        (self.output / 'keep.txt').write_text('user file')
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('already exists', result.stderr)
        self.assertEqual(list(self.output.iterdir()), [self.output / 'keep.txt'])

    def test_output_cannot_be_inside_shared_sources(self):
        output = self.source / 'plugins/generated'
        result = self.build(output)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())

    def test_invalid_yaml_does_not_leave_partial_package(self):
        skill = self.source / 'plugins/gox-code-rules/skills/go/SKILL.md'
        skill.write_text('---\nname: go\ndescription: invalid: yaml\n---\n')
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('SKILL.md', result.stderr)
        self.assertFalse(self.output.exists())

    def test_missing_reference_fails_before_output(self):
        (self.source / 'plugins/gox-code-rules/skills/go/references/http.md').unlink()
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('http.md', result.stderr)
        self.assertFalse(self.output.exists())

    def test_symlink_in_shared_skill_is_rejected(self):
        skill = self.source / 'plugins/gox-code-rules/skills/go'
        (skill / 'outside').symlink_to(self.root)
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('symlink', result.stderr)
        self.assertFalse(self.output.exists())

    def test_nudges_run_after_source_removed_and_package_relocated(self):
        self.built()
        shutil.rmtree(self.source)
        relocated = self.root / 'relocated package'
        self.output.rename(relocated)
        self.output = relocated
        for event in ['SessionStart', 'SubagentStart']:
            result = self.hook('gox-code-rules', event)
            self.assertEqual(result.returncode, 0, result.stderr)
            specific = json.loads(result.stdout)['hookSpecificOutput']
            self.assertEqual(specific['hookEventName'], event)
            text = specific['additionalContext']
            paths = re.findall(r'`([^`]+/SKILL.md)`', text)
            self.assertTrue(paths)
            self.assertTrue(all(Path(p).is_file() for p in paths))
            self.assertNotIn('Skill tool', text)
            self.assertNotIn('python/SKILL.md', text)

    def test_guard_scans_pending_commits_and_handles_each_scanner_result(self):
        self.built()
        repo = self.root / 'repo'
        subprocess.run(['git', 'init', '-q', str(repo)], check=True)
        subprocess.run(['git', '-C', str(repo), 'config', 'user.name', 'Test'], check=True)
        subprocess.run(['git', '-C', str(repo), 'config', 'user.email', 'test@example.com'], check=True)
        (repo / 'file').write_text('fixture')
        subprocess.run(['git', '-C', str(repo), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(repo), 'commit', '-qm', 'fixture'], check=True)
        scanner = self.root / 'scanner'
        log = self.root / 'scan-args'
        payload = {'hook_event_name': 'PreToolUse', 'tool_name': 'Bash',
                   'cwd': str(repo), 'tool_input': {'command': 'git push origin main'}}
        finding = json.dumps([{'RuleID': 'test', 'File': 'file', 'StartLine': 1,
                               'Commit': '0123456789abcdef', 'Fingerprint': 'test:1',
                               'Secret': 'DO-NOT-PRINT'}])
        for code in [0, 1, 2]:
            scanner.write_text('#!/bin/bash\nprintf "%s\\n" "$@" > "$SCAN_LOG"\n'
                               + "printf '%s\\n' '" + finding + "'\nexit " + str(code) + '\n')
            scanner.chmod(0o755)
            result = self.hook('gox-guard', 'PreToolUse', payload,
                               {'GOX_GUARD_BIN': str(scanner), 'SCAN_LOG': str(log)})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('--redact', log.read_text())
            self.assertIn('--log-opts=HEAD --not --remotes', log.read_text())
            if code == 0:
                self.assertEqual(result.stdout, '')
            else:
                self.assertEqual(json.loads(result.stdout)['hookSpecificOutput']['permissionDecision'], 'deny')
                self.assertNotIn('DO-NOT-PRINT', result.stdout)
        # A controlled PATH excludes betterleaks even on machines with it installed.
        bin_dir = self.root / 'bin'
        bin_dir.mkdir()
        for name in ['bash', 'cat', 'grep', 'git', 'jq']:
            (bin_dir / name).symlink_to(shutil.which(name))
        result = self.hook('gox-guard', 'PreToolUse', payload, {'PATH': str(bin_dir)})
        self.assertEqual(json.loads(result.stdout)['hookSpecificOutput']['permissionDecision'], 'deny')
        self.assertIn('not installed', result.stdout)


if __name__ == '__main__':
    unittest.main()
