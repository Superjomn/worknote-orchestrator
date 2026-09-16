#!/usr/bin/env python3
"""Build/assert R1–R6 fixtures. Skill actions are performed separately by an agent."""
from pathlib import Path
import json
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
TEMPLATES = ROOT / 'skills/research-memory/templates'
SCANNER = ROOT / 'skills/worknote-orchestrate/scripts/wn_scan.py'


def section(text, heading):
    match = re.search(r'^## ' + re.escape(heading) + r'\n(.*?)(?=^## |\Z)', text, re.M | re.S)
    assert match, f'missing section {heading}'
    return match.group(1)


def without_section(text, heading):
    match = re.search(r'^## ' + re.escape(heading) + r'\n(.*?)(?=^## |\Z)', text, re.M | re.S)
    assert match, f'missing section {heading}'
    return text[:match.start(1)] + '<SECTION>' + text[match.end(1):]


def snapshot(root):
    return {str(p.relative_to(root)): p.read_bytes() for p in root.rglob('*') if p.is_file()}


def setup(case, scratch):
    scratch.mkdir(parents=True, exist_ok=True)
    # A fresh directory keeps fixture cleanup away from unrelated data.
    if any(scratch.iterdir()):
        raise ValueError('R cases require an empty scratch directory')
    store = scratch / 'research-memory'
    store.mkdir()
    for name in ('MEMORY.md', 'configs.md', 'runbook.md', 'jobs.md', 'blockers.md'):
        shutil.copyfile(TEMPLATES / name, store / name)
    (store / 'tasks').mkdir()
    (store / 'MEMORY.md').write_text('''# Fixture memory

## Current focus
- #1 measure baseline

## Validated conclusions
- Baseline throughput is 1234 tok/s — job j1, /logs/base.txt, 2026-09-16 → tasks/task-4.md

## Reference configs
- base → configs.md#base (status: working)

## Pointers
- jobs.md
''')
    (store / 'configs.md').write_text('''# Configs

| id/path | workdir | status | key knobs | evidence |
|---|---|---|---|---|
| base | /work/base | working | tp=4 | j1, /logs/base.txt |
''')
    (store / 'jobs.md').write_text('''# Jobs

| timestamp | job id | purpose | config ref | owner | status | result ptr |
|---|---|---|---|---|---|---|
| 2026-09-16 10:00 | j1 | baseline | configs.md#base | agent | finished | /logs/base.txt |
''')
    task = '''# Task #1

## Brief
- task: measure baseline
- workdir: /work/base
- worknote: Scratch.md#1
- context: none
- blockers: none

## Attempts

### Attempt 1 — 2026-09-16 10:00
- task: measure baseline
- owner: agent
- context: none
- tried: submitted j2
- jobs: j2
- outcome: active
- next step: monitor j2

## Working notes

## Outcome
'''
    (store / 'tasks/task-1.md').write_text(task)
    (store / 'tasks/task-4.md').write_text('# Task #4\n\n## Outcome\n- conclusion: baseline verified — j1, /logs/base.txt\n- promoted: MEMORY.md\n')
    worknote = '# Study\n\n<<RUNNING#1 owner=agent job=j2 since=2026-09-16T10:00 task: measure baseline>>\n'
    if case == 'R1':
        (store / 'blockers.md').write_text('''# Blockers

### BLOCKED#1 — old question
- timestamp: 2026-09-16 09:00
- workdir: /work/base
- placeholder ref: Scratch.md#1
- task file: tasks/task-1.md
- Question: lower batch?
- Evidence: /logs/old.txt
- Answer:

### BLOCKED#1 — current question
- timestamp: 2026-09-16 10:00
- workdir: /work/base
- placeholder ref: Scratch.md#1
- task file: tasks/task-1.md
- Question: skip failed point?
- Evidence: /logs/new.txt
- Answer: skip it
''')
    elif case == 'R4':
        with (store / 'jobs.md').open('a') as f:
            f.write('| 2026-09-16 10:01 | j2 | baseline | configs.md#base | agent | running | /receipts/j2.txt |\n')
        worknote = '# Study\n\nThe human deleted the task marker.\n'
    elif case == 'R5':
        task = task.replace('- outcome: active', '- outcome: superseded by Attempt 2')
        task = task.replace('## Working notes', '''### Attempt 2 — 2026-09-16 10:05
- task: measure latency
- owner: tab:new
- context: latency only
- tried: planning
- jobs: none
- outcome: active
- next step: collect latency

## Working notes''')
        (store / 'tasks/task-1.md').write_text(task)
        worknote = '# Study\n\n<<! latency only >>\n\n<<RUNNING#1 owner=tab:new job=pending since=2026-09-16T10:05 task: measure latency>>\n'
    elif case == 'R6':
        (store / 'tasks/task-1.md').unlink()
        worknote = '# Study\n\n<<! @memory use the validated baseline >>\n\n<<report baseline throughput>>\n'
    (scratch / 'Scratch.md').write_text(worknote)
    shutil.copytree(store, scratch / 'research-memory.orig')
    shutil.copyfile(scratch / 'Scratch.md', scratch / 'Scratch.md.orig')
    print(f'setup {case} done — {scratch}')


def verify(case, scratch):
    store, orig = scratch / 'research-memory', scratch / 'research-memory.orig'
    before, after = snapshot(orig), snapshot(store)
    def unchanged_except(*names):
        assert {k:v for k,v in before.items() if k not in names} == {k:v for k,v in after.items() if k not in names}, 'unrelated store content changed'
    def capture(name):
        text = (scratch / name).read_text()
        assert text.strip(), f'empty capture {name}'
        return text
    if case == 'R1':
        unchanged_except()
        assert re.search(r'latest|already answered|already.*filled', capture('refusal.txt'), re.I), 'must explain latest-answer refusal'
    elif case == 'R2':
        unchanged_except('MEMORY.md')
        old, new = (orig / 'MEMORY.md').read_text(), (store / 'MEMORY.md').read_text()
        assert not section(new, 'Current focus').strip(), 'focus must be empty'
        assert without_section(old, 'Current focus') == without_section(new, 'Current focus'), 'other index sections changed'
    elif case == 'R3':
        unchanged_except()
        answer = capture('answer.txt')
        assert '1234' in answer and 'MEMORY.md' in answer, 'supported throughput/evidence lost'
        assert re.search(r'energy.*(not found|unknown|not recorded)', answer, re.I), 'missing energy must be explicit'
        assert not re.search(r'\d\s*(joules|J/token)', answer), 'invented energy value'
    elif case == 'R4':
        unchanged_except('tasks/task-1.md')
        old, new = (orig / 'tasks/task-1.md').read_text(), (store / 'tasks/task-1.md').read_text()
        assert without_section(old, 'Attempts') == without_section(new, 'Attempts'), 'only active Attempt should close'
        assert re.search(r'outcome:.*cancelled', section(new, 'Attempts')), 'dispatch cancellation missing'
        assert not section(new, 'Outcome').strip(), 'cancelled dispatch cannot become completed result'
        assert 'j2' in capture('status-output.txt') and re.search(r'running|orphaned', capture('status-output.txt')), 'live job handoff missing'
    elif case == 'R5':
        unchanged_except('tasks/task-1.md')
        old, new = (orig / 'tasks/task-1.md').read_text(), (store / 'tasks/task-1.md').read_text()
        assert without_section(old, 'Working notes') == without_section(new, 'Working notes'), 'newer Attempt/Outcome altered'
        notes = section(new, 'Working notes')
        assert 'Attempt 1' in notes and '/logs/late.txt' in notes, 'late evidence must retain origin'
        assert re.search(r'not updated|not published|superseded', capture('result.txt')), 'publication failure not reported'
    elif case == 'R6':
        assert set(after) == set(before) | {'tasks/task-5.md'}, 'exactly one task ID should be reserved'
        unchanged_except('tasks/task-5.md', 'MEMORY.md')
        task = (store / 'tasks/task-5.md').read_text()
        assert '1234' in section(task, 'Outcome') and 'promoted:' in section(task, 'Outcome'), 'result must be saved'
        assert 'report baseline throughput' in section(task, 'Attempts'), 'dispatch task snapshot absent'
        assert '@memory use the validated baseline' in section(task, 'Attempts'), 'canonical context absent'
        output = subprocess.check_output([sys.executable, str(SCANNER), str(scratch/'Scratch.md'), '--memory', str(store)])
        scan = json.loads(output)
        assert scan['next_id'] == 6 and not scan['placeholders'], 'completed fill must retain ID and remove its marker'
        current = (scratch/'Scratch.md').read_text()
        assert '1234' in current, 'conclusion not published'
        prefix, suffix = (scratch/'Scratch.md.orig').read_text().split('<<report baseline throughput>>')
        assert current.startswith(prefix) and current.endswith(suffix), 'surrounding human text changed'
        assert len(scan['context_blocks']) == 1, 'persistent context lost'
    else:
        raise ValueError(case)
    if case != 'R6':
        assert (scratch/'Scratch.md').read_bytes() == (scratch/'Scratch.md.orig').read_bytes(), 'worknote changed'
    print(f'PASS {case}')


if __name__ == '__main__':
    mode, case, directory = sys.argv[1:]
    if case not in {f'R{i}' for i in range(1,7)}:
        raise ValueError(case)
    {'setup': setup, 'assert': verify}[mode](case, Path(directory).resolve())
