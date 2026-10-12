"""Behavioral regressions for scanner guards and durable ID reservations."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / 'skills/worknote-orchestrate/scripts'
sys.path.insert(0, str(SCRIPTS))
import wn_scan


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.note = self.root / 'Study.md'
        self.memory = self.root / 'Study.memory'
        self.memory.mkdir()
        self.marker = '<<RUNNING#1 owner=agent:a attempt=token-a job=pending task: measure>>'
        self.note.write_text('<<! @dir:/work/a baseline >>\n# Study\n' + self.marker + '\n')
        self.original = wn_scan.scan(str(self.note), str(self.memory))['placeholders'][0]

    def command(self, script, *args):
        return [sys.executable, '-B', str(SCRIPTS / script), str(self.note),
                '--memory', str(self.memory), *args]

    def guard(self, *extra):
        return subprocess.run(self.command('wn_scan.py', '--id', '1',
            '--expect-attempt', self.original['attempt'],
            '--expect-owner', self.original['owner'],
            '--expect-fingerprint', self.original['fingerprint'], *extra),
            capture_output=True, text=True)

    def snapshot(self):
        return {str(p.relative_to(self.root)): p.read_bytes()
                for p in self.root.rglob('*') if p.is_file()}

    def test_guard_is_read_only_and_accepts_unchanged_attempt(self):
        before = self.snapshot()
        result = self.guard()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['attempt'], 'token-a')
        self.assertEqual(before, self.snapshot())

    def test_late_old_agent_cannot_publish_after_takeover(self):
        self.note.write_text(self.note.read_text().replace('attempt=token-a', 'attempt=token-b'))
        before = self.snapshot()
        result = self.guard()
        self.assertEqual(result.returncode, 2)
        self.assertIn('ownership changed', result.stderr)
        self.assertEqual(result.stdout, '')
        self.assertEqual(before, self.snapshot())

    def test_owner_change_without_token_change_is_rejected(self):
        self.note.write_text(self.note.read_text().replace('owner=agent:a', 'owner=tab:b'))
        self.assertEqual(self.guard().returncode, 2)

    def test_human_task_or_context_edits_reject_publication(self):
        original_text = self.note.read_text()
        for old, new in [('measure', 'measure again'), ('baseline', 'new baseline'),
                         ('@dir:/work/a', '@dir:/work/b')]:
            with self.subTest(edit=new):
                self.note.write_text(original_text.replace(old, new))
                result = self.guard()
                self.assertEqual(result.returncode, 2)
                self.assertIn('task/context changed', result.stderr)

    def test_cancellation_does_not_mutate_running_job_observation(self):
        jobs = self.memory / 'jobs.md'
        jobs.write_text('| now | job-1 | task=1 attempt=token-a | c | agent:a | running | log |\n')
        self.note.write_text('# Study\n')
        before = self.snapshot()
        self.assertEqual(self.guard().returncode, 2)
        self.assertEqual(before, self.snapshot())

    def test_legacy_claim_is_readable_but_guard_fails_closed(self):
        self.note.write_text(self.note.read_text().replace(' attempt=token-a', ''))
        plain = subprocess.run(self.command('wn_scan.py'), capture_output=True, text=True)
        self.assertEqual(plain.returncode, 0)
        self.assertIsNone(json.loads(plain.stdout)['placeholders'][0]['attempt'])
        self.assertEqual(self.guard().returncode, 2)

    def test_marker_move_job_update_and_blocker_answer_keep_fingerprint(self):
        self.note.write_text(self.note.read_text().replace('# Study\n', '# Study\nmore prose\n')
                            .replace('job=pending', 'job=job-1'))
        self.assertEqual(self.guard().returncode, 0)
        self.note.write_text(self.note.read_text().replace('RUNNING#1', 'BLOCKED#1')
                            .replace('measure>>', 'measure\nQ: retry?\nA: use @memory>>'))
        self.assertEqual(self.guard().returncode, 0)

    def test_literal_question_fields_survive_claim_and_blocking(self):
        task = 'explain Q: queue latency at load 10\nQ: include literal task line'
        self.note.write_text('<<#1 ' + task + '>>')
        pending = wn_scan.scan(str(self.note), str(self.memory))['placeholders'][0]
        self.note.write_text('<<RUNNING#1 owner=agent:a attempt=token-a task: ' + task + '>>')
        self.original = wn_scan.scan(str(self.note), str(self.memory))['placeholders'][0]
        self.assertEqual(self.original['task'], task)
        self.assertEqual(self.original['fingerprint'], pending['fingerprint'])
        self.note.write_text(self.note.read_text().replace('RUNNING#1', 'BLOCKED#1')
                            .replace('>>', '\nQ: actual blocker?\nA: metadata answer>>'))
        self.assertEqual(self.guard().returncode, 0)
        self.note.write_text(self.note.read_text().replace('load 10', 'load 100'))
        self.assertEqual(self.guard().returncode, 2)

    def test_inline_legacy_blocker_cannot_pass_guard(self):
        self.note.write_text('<<BLOCKED#1 owner=agent:a attempt=token-a task: measure Q: retry?>>')
        self.original = wn_scan.scan(str(self.note), str(self.memory))['placeholders'][0]
        self.assertEqual(self.original['question'], 'retry?')
        result = self.guard()
        self.assertEqual(result.returncode, 2)
        self.assertIn('legacy BLOCKED encoding', result.stderr)

    def test_multiline_legacy_blocker_does_not_break_other_tasks(self):
        self.note.write_text(self.note.read_text() +
            '\n<<BLOCKED#2 owner=agent task: measure\nQ: retry with a smaller batch\n'
            'or skip the experiment?\nA: use batch 2>>')
        before = self.snapshot()
        plain = subprocess.run(self.command('wn_scan.py'), capture_output=True, text=True)
        self.assertEqual(plain.returncode, 0, plain.stderr)
        old = json.loads(plain.stdout)['placeholders'][1]
        self.assertEqual(old['blocker_format'], 'legacy')
        self.assertEqual(old['question'], 'retry with a smaller batch\nor skip the experiment?')
        self.assertEqual(self.guard().returncode, 0)
        self.assertEqual(before, self.snapshot())

    def test_legacy_newline_question_and_inline_answer_remain_readable(self):
        old = wn_scan.parse_marker('BLOCKED#2 owner=agent task: measure\nQ: retry? A: yes')
        self.assertEqual(old['question'], 'retry?')
        self.assertEqual(old['answer'], 'yes')
        self.assertEqual(old['blocker_format'], 'legacy')

    def test_duplicate_marker_is_never_chosen(self):
        self.note.write_text(self.note.read_text() + self.marker)
        self.assertEqual(self.guard().returncode, 2)

    def test_partial_guard_arguments_are_rejected(self):
        result = subprocess.run(self.command('wn_scan.py', '--id', '1',
                                '--expect-attempt', 'token-a'), capture_output=True)
        self.assertEqual(result.returncode, 2)

    def test_directives_within_same_body_are_last_wins(self):
        self.assertEqual(wn_scan.parse_directives('@run @memory'), {'memory': True})
        self.assertEqual(wn_scan.parse_directives('@memory @run'), {'run': True})
        self.assertEqual(wn_scan.parse_directives('@dir:/a @dir:/b'), {'dir': '/b'})

    def test_state_words_and_malformed_ids_are_plain_tasks(self):
        for text in ['RUNNING experiments summary', 'BLOCKED resources report',
                     'RUNNING#1oops summary', '#2abc measure']:
            with self.subTest(text=text):
                parsed = wn_scan.parse_marker(text)
                self.assertEqual(parsed['state'], 'pending')
                self.assertEqual(parsed['task'], text)
                self.assertIsNone(parsed['id'])

    def test_nested_fences_do_not_expose_fake_headings(self):
        for fence in ['````', '~~~~']:
            with self.subTest(fence=fence):
                lines = [fence + 'markdown', fence[:3] + 'python', '# hidden',
                         fence + 'not-a-close', '# still hidden', fence, '# visible']
                self.assertEqual(wn_scan.headings(lines), [(7, 1, 'visible')])

    def test_fingerprint_preserves_block_boundaries(self):
        a = wn_scan.task_fingerprint('task', [{'text': 'a | b'}], {})
        b = wn_scan.task_fingerprint('task', [{'text': 'a'}, {'text': 'b'}], {})
        self.assertNotEqual(a, b)

    def test_empty_attempt_context_does_not_consume_following_field(self):
        tasks = self.memory / 'tasks'
        tasks.mkdir()
        self.note.write_text(self.marker)
        for following in ['- tried: none', '', '## Outcome\n- context: unrelated']:
            with self.subTest(following=following):
                (tasks / 'task-1.md').write_text(
                    '## Attempts\n### Attempt 1\n- context: \t\n' + following + '\n')
                self.assertEqual(wn_scan.attempt_context(str(self.memory), 1), '')
                result = wn_scan.scan(str(self.note), str(self.memory))
                self.assertFalse(result['placeholders'][0]['context_drift'])

    def test_heading_containing_marker_closes_previous_scope(self):
        self.note.write_text('# A\n<<! @dir:/a >>\n# B <<#1 title>>\n<<#2 task>>\n')
        result = wn_scan.scan(str(self.note), str(self.memory))
        for placeholder in result['placeholders']:
            self.assertEqual(placeholder['section'], 'B <<#1 title>>')
            self.assertEqual(placeholder['context_chain'], [])
            self.assertIsNone(placeholder['effective_dir'])

    def test_heading_containing_context_scopes_it_to_that_heading(self):
        self.note.write_text('# A <<! @memory >>\n<<#1 task>>\n# B\n<<#2 task>>\n')
        result = wn_scan.scan(str(self.note), str(self.memory))
        self.assertEqual(result['placeholders'][0]['directives'], {'memory': True})
        self.assertEqual(result['placeholders'][1]['context_chain'], [])

    def test_marker_tail_cannot_create_a_heading(self):
        self.note.write_text('# A\n<<! @memory >>\n<<#1 multiline\n>># fake\n<<#2 task>>')
        result = wn_scan.scan(str(self.note), str(self.memory))
        self.assertEqual(result['placeholders'][1]['section'], 'A')
        self.assertEqual(result['placeholders'][1]['directives'], {'memory': True})

    def test_concurrent_allocations_do_not_collide(self):
        before_note = self.note.read_bytes()
        processes = [subprocess.Popen(self.command('wn_allocate.py', '--count', '3'),
                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) for _ in range(8)]
        ids = []
        for process in processes:
            out, err = process.communicate(timeout=20)
            self.assertEqual(process.returncode, 0, err)
            ids.extend(json.loads(out)['reserved_ids'])
        self.assertEqual(len(ids), 24)
        self.assertEqual(len(set(ids)), 24)
        self.assertEqual(sorted(ids), list(range(2, 26)))
        for pid in ids:
            reserved = (self.memory / 'tasks' / f'task-{pid}.md').read_text()
            self.assertIn(f'# Task #{pid}', reserved)
            self.assertNotIn('### Attempt', reserved)
            self.assertEqual(reserved.partition('## Outcome')[2].strip(), '')
        self.assertEqual(before_note, self.note.read_bytes())

    def test_completed_fill_and_failed_stamp_do_not_recycle_ids(self):
        first = subprocess.run(self.command('wn_allocate.py'), capture_output=True, text=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(json.loads(first.stdout)['reserved_ids'], [2])
        # All visible markers disappeared; task-2 still pins the high-water mark.
        self.note.write_text('A completed conclusion.\n')
        second = subprocess.run(self.command('wn_allocate.py'), capture_output=True, text=True)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(json.loads(second.stdout)['reserved_ids'], [3])
        # Simulate death immediately after exclusive creation, before template writing.
        (self.memory / 'tasks' / 'task-4.md').touch()
        third = subprocess.run(self.command('wn_allocate.py'), capture_output=True, text=True)
        self.assertEqual(third.returncode, 0, third.stderr)
        self.assertEqual(json.loads(third.stdout)['reserved_ids'], [5])

    def test_allocator_validates_before_mutation(self):
        before = self.snapshot()
        invalid = subprocess.run(self.command('wn_allocate.py', '--count', '0'), capture_output=True)
        self.assertEqual(invalid.returncode, 2)
        self.assertEqual(before, self.snapshot())
        self.note.write_text(self.note.read_text() + self.marker)
        before = self.snapshot()
        duplicate = subprocess.run(self.command('wn_allocate.py'), capture_output=True)
        self.assertEqual(duplicate.returncode, 2)
        self.assertEqual(before, self.snapshot())


if __name__ == '__main__':
    unittest.main()
