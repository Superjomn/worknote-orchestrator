"""Offline packaging and installer checks; all installs use temporary targets."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
NAMES = ('research-memory', 'worknote-orchestrate')


class PackagingTests(unittest.TestCase):
    def test_manifests_and_catalogs(self):
        claude = json.loads((ROOT / '.claude-plugin/plugin.json').read_text())
        codex = json.loads((ROOT / '.codex-plugin/plugin.json').read_text())
        for key in ('name', 'version', 'author', 'repository', 'homepage'):
            self.assertEqual(claude[key], codex[key])
        self.assertEqual(codex['version'], '0.9.0')
        self.assertRegex(codex['name'], r'^[a-z0-9]+(?:-[a-z0-9]+)*$')
        self.assertEqual(codex['skills'], './skills/')
        self.assertTrue((ROOT / codex['skills']).is_dir())
        for path in ('.claude-plugin/marketplace.json', '.agents/plugins/marketplace.json'):
            catalog = json.loads((ROOT / path).read_text())
            self.assertEqual(catalog['name'], codex['name'])
            self.assertEqual(len(catalog['plugins']), 1)
            entry = catalog['plugins'][0]
            self.assertEqual(entry['name'], codex['name'])
            if isinstance(entry['source'], dict):
                self.assertEqual(entry['source']['source'], 'local')
                source = entry['source']['path']
                self.assertEqual(entry['policy'], {'installation': 'AVAILABLE', 'authentication': 'ON_INSTALL'})
            else:
                source = entry['source']
                self.assertEqual(entry['version'], codex['version'])
            self.assertTrue(source.startswith('./'))
            self.assertTrue((ROOT / source).resolve().is_relative_to(ROOT))
            self.assertTrue((ROOT / source / '.codex-plugin/plugin.json').is_file())

    def test_skill_frontmatter(self):
        self.assertEqual({p.name for p in (ROOT / 'skills').iterdir() if p.is_dir()}, set(NAMES))
        for name in NAMES:
            text = (ROOT / 'skills' / name / 'SKILL.md').read_text()
            self.assertTrue(text.startswith('---\n'))
            frontmatter = text.split('---\n', 2)[1]
            # These manifests deliberately use plain, single-line YAML scalars.
            fields = dict(re.findall(r'^(name|description):\s*(\S[^\n]*)$', frontmatter, re.M))
            self.assertEqual(fields['name'], name)
            self.assertTrue(fields['description'].strip())
            self.assertRegex(frontmatter, r'(?m)^  version: 0\.9\.0$')


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='codex skills ')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.target = self.base / 'target with spaces'
        self.env = dict(os.environ, HOME=str(self.base / 'home'))
        self.env.pop('CODEX_SKILLS_DIR', None)

    def install(self, *args, target=True, success=True):
        command = ['bash', str(ROOT / 'scripts/install-codex-skills.sh')]
        if target:
            command += ['--target', str(self.target)]
        result = subprocess.run(command + list(args), cwd=self.base, env=self.env,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def test_symlinks_and_idempotency(self):
        self.install()
        before = {n: (self.target / n).lstat().st_ino for n in NAMES}
        self.install()
        for name in NAMES:
            dest = self.target / name
            self.assertTrue(dest.is_symlink())
            self.assertEqual(dest.resolve(), ROOT / 'skills' / name)
            self.assertEqual(dest.lstat().st_ino, before[name])

    def test_copy_and_idempotency(self):
        self.install('--copy')
        before = {n: (self.target / n).stat().st_ino for n in NAMES}
        self.install('--copy')
        for name in NAMES:
            dest = self.target / name
            self.assertFalse(dest.is_symlink())
            self.assertEqual(dest.stat().st_ino, before[name])
            source = ROOT / 'skills' / name
            for src in source.rglob('*'):
                if src.is_file() and '__pycache__' not in src.parts:
                    self.assertEqual(src.read_bytes(), (dest / src.relative_to(source)).read_bytes())

    def test_refuse_conflicts_before_installing_either_skill(self):
        for kind in ('directory', 'file', 'link', 'broken-link'):
            with self.subTest(kind=kind):
                self.target.mkdir()
                conflict = self.target / NAMES[1]
                if kind == 'directory':
                    conflict.mkdir()
                    (conflict / 'keep').write_text('user content')
                elif kind == 'file':
                    conflict.write_text('user content')
                else:
                    conflict.symlink_to(self.base if kind == 'link' else self.base / 'missing')
                for mode in ((), ('--copy',)):
                    self.assertIn('refusing to overwrite', self.install(*mode, success=False).stderr)
                    self.assertFalse((self.target / NAMES[0]).exists())
                self.assertTrue(conflict.exists() or conflict.is_symlink())
                shutil.rmtree(self.target)

    def test_refuse_modified_copy(self):
        self.install('--copy')
        skill = self.target / NAMES[0] / 'SKILL.md'
        skill.write_text('local edits')
        self.install('--copy', success=False)
        self.assertEqual(skill.read_text(), 'local edits')

    def test_default_env_and_flag_precedence(self):
        self.install(target=False)
        self.assertTrue((Path(self.env['HOME']) / '.agents/skills' / NAMES[0]).is_symlink())
        env_target = self.base / 'env target'
        self.env['CODEX_SKILLS_DIR'] = str(env_target)
        self.install(target=False)
        self.assertTrue((env_target / NAMES[1]).is_symlink())
        shutil.rmtree(env_target)
        self.install()
        self.assertFalse(env_target.exists())

    def test_bad_arguments(self):
        self.install('--target', success=False)
        self.install('--unknown', success=False)
        self.assertFalse(self.target.exists())


if __name__ == '__main__':
    unittest.main()
