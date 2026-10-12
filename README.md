# worknote-orchestrator

Two skills for filling human-owned worknote placeholders from existing evidence or real jobs, with shared research memory and batched feedback. The instructions support Claude Code and Codex; the plugin packages the same skills for both hosts.

- **worknote-orchestrate** coordinates a whole worknote, works one named task interactively, or reports a read-only dashboard. Persistent `<<! ... >>` context blocks apply only to their Markdown scopes. Workers receive only their task's inherited context.
- **research-memory** stores evidence, configs, job observations, runbooks, blockers, and restartable task records beside the worknote. Its index stays small; action details and queries load from references only when needed.

## Claude Code quickstart

Treat AI as a research intern: write the assignment once, let it run multi-turn
experiments, and come back to an evidence-backed report. This worknote asks which
inference backend best serves Qwen3-30B: vLLM or SGLang. The agent sets up the
experiment, runs and troubleshoots benchmarks, compares results, and fills the
report without needing you to steer every step within the agreed scope.

Use an installed, authenticated Claude Code, Git, Bash, and Python 3.10+ on a
machine with suitable NVIDIA GPU capacity and access to the model weights.
The orchestration helpers use only Python's standard library; the inference
backends need their own dependencies. Adjust the resource budget below before
starting; this is a real experiment, not a canned benchmark.

Clone the plugin and create a research directory:

```bash
git clone https://github.com/Superjomn/worknote-orchestrator.git
cd worknote-orchestrator
plugin_dir="$PWD"
mkdir -p ../inference-study
cd ../inference-study
```

Save this as `my-research-task.md` in that directory:

```markdown
# Best inference backend for Qwen3-30B

<<! @dir:. @run
Use Qwen/Qwen3-30B-A3B on this machine's available GPUs. Work in this
worknote's directory, with separate environments for vLLM and SGLang.
I authorize local dependency setup, model download, and sequential benchmark
runs for up to 4 hours total; no paid cloud resources. Run a small canary per
backend, then continue autonomously without an interactive canary review.
Diagnose failures and retry at most twice per configuration within the budget.
Follow the sections in order; later tasks depend on earlier evidence. Save exact
commands, versions, configs, logs, and raw measurements in research memory.
If blocked or out of budget, preserve partial results and report what is missing.
>>

## 1. Environment and experiment plan
<<Inspect GPU/VRAM, drivers, disk space, and model access; set up isolated backend
environments. Pin the same model revision, precision, tensor parallelism, and
prompt set for both backends. Define a reproducible workload with 512 input and
128 output tokens, concurrency 1/8/32, warmup, and three measured repeats.
Record versions, hardware, and the plan before benchmarking.>>

## 2. vLLM benchmark
<<After setup, validate vLLM with a canary, then run the workload matrix.
Measure output tokens/s, p50/p95 time to first token, p95 inter-token latency,
peak GPU memory, and errors. Investigate failures within the retry budget;
summarize successful runs and limitations with links to raw evidence.>>

## 3. SGLang benchmark
<<After vLLM releases the GPUs, validate SGLang with a canary and run the same
workload matrix on the same hardware. Collect the same metrics and investigate
failures within the retry budget. Document any unavoidable config differences
and cite the raw evidence.>>

## 4. Comparison
<<! @memory Use the saved benchmark evidence only; do not launch more jobs. >>
<<After both benchmarks, compare throughput, latency, memory, and reliability
at each concurrency. Show repeat variability and flag unfair or missing
comparisons. Identify the best measured configuration per backend.>>

## 5. Final recommendation report
<<! @memory Base the recommendation on the completed comparison and its sources. >>
<<Recommend a backend and config for throughput-oriented batch inference and
for latency-sensitive serving. Explain tradeoffs, cite measurements and
reproduction commands, and state limitations or follow-up experiments.
If evidence is incomplete, give a provisional verdict rather than inventing results.>>
```

Each `<<...>>` is a sub-task to fill. Persistent `<<! ... >>` blocks provide
context: the top block applies to every section, while each `@memory` block
applies only to its own section and overrides `@run` there. `@dir:.` selects the
research directory. These directives are planning hints; task order, dependencies,
and the execution budget are instructions to the agent, not a scripted scheduler.

Start Claude Code from the research directory:

```bash
claude --plugin-dir "$plugin_dir"
```

`--plugin-dir` loads the local checkout for this session. Inside Claude Code,
send these requests **one at a time**, waiting for each to finish:

```text
/worknote-orchestrator:research-memory init my-research-task.md
/worknote-orchestrator:worknote-orchestrate my-research-task.md
/worknote-orchestrator:worknote-orchestrate my-research-task.md status
```

Init creates the five index/ledger files in `my-research-task.memory/`.
Orchestration records task attempts, job observations, and evidence there, then
replaces each completed placeholder with conclusions while preserving context
blocks. Keep the agent session running for the experiments. Missing permissions,
resources, or unresolved choices can still require input; blockers are collected
for you. The `status` request is read-only and reconciles markers with memory.
The scanner alone does not execute tasks or fill the report.

An illustrative filled excerpt follows (**fictional numbers**, not measured
backend performance; actual conclusions depend on your hardware and runs):

```markdown
## 4. Comparison
At concurrency 32, vLLM delivered 1,200 output tok/s and SGLang 1,350 output
tok/s (repeat ranges: 1,180–1,220 and 1,320–1,380). SGLang was 12.5% faster.
At concurrency 1, vLLM had lower p95 TTFT: 80 ms versus 95 ms.
Sources: [vLLM runs](my-research-task.memory/results/vllm.csv),
[SGLang runs](my-research-task.memory/results/sglang.csv).

## 5. Final recommendation report
Choose SGLang for this batch workload and vLLM for low-concurrency interactive
serving. Reproduce with the pinned configs and commands in
[the runbook](my-research-task.memory/runbook.md). This conclusion covers only
the tested hardware and token lengths; longer-context workloads remain untested.
```

The result paths above are illustrative artifacts saved by the agent, not files
created by init. A successful final status might read: “No actionable placeholders
remain; all recorded benchmark jobs have terminal evidence; no unresolved blockers.”
Detailed commands and intermediate results stay in memory, leaving the worknote
as the report you asked your intern to deliver.

## Install and use

For Claude Code:

```text
/plugin marketplace add Superjomn/worknote-orchestrator
/plugin install worknote-orchestrator@worknote-orchestrator
```

### Codex CLI install

Requires Bash and Python 3.10+. For standalone skills, run from this checkout:

```bash
bash scripts/install-codex-skills.sh
# Alternatives: a project-local skills directory, or copies instead of links
bash scripts/install-codex-skills.sh --target /path/to/project/.agents/skills
bash scripts/install-codex-skills.sh --copy --target /path/to/skills
```

The default target is `$HOME/.agents/skills`; `CODEX_SKILLS_DIR` overrides it and
`--target` takes precedence. Both sibling skills and all resources stay together.
Matching symlinks or identical copies are preserved on repeated installs. Conflicting
files, directories, or links cause refusal before either skill is installed. Copies
are snapshots: when the source changes, choose a fresh target or explicitly remove
your old copies after checking for local edits. Symlinks follow checkout updates;
keep the checkout in place. Use `/skills` in Codex to browse; restart if a change
is not picked up. Choose either standalone skills or the plugin to avoid duplicates.

For the plugin marketplace route, run from the checkout:

```bash
codex plugin marketplace add "$PWD"   # or: codex plugin marketplace add Superjomn/worknote-orchestrator
codex plugin add worknote-orchestrator@worknote-orchestrator
codex plugin list
```

The repo catalog `.agents/plugins/marketplace.json` uses a `./` source that resolves from the repository root. The
`.codex-plugin/plugin.json` compatibility manifest points to `./skills/` and uses
version `0.9.0`, matching Claude. This layout was verified with Codex CLI 0.162.1
using a temporary config/cache. Plugin skills are namespaced (Codex 0.162.1 lists them as
`worknote-orchestrator:research-memory` and `worknote-orchestrator:worknote-orchestrate`);
use the entry shown by `/skills`. No Claude environment
variable is needed. See the official [skill documentation](https://developers.openai.com/codex/skills)
and [plugin packaging documentation](https://developers.openai.com/codex/plugins/build).

### Codex quickstart

Use an installed, authenticated Codex CLI with the same Git, Bash, Python, GPU,
model access, and backend dependencies described in the Claude Code quickstart.
Clone the repository and create `inference-study` as above. Save the **same
`my-research-task.md` example above**, including its resource budget and scoped
context blocks. With the standalone skills installed, start from that research
directory:

```bash
codex
```

Send these requests **one at a time**, waiting for each to finish:

```text
$research-memory init my-research-task.md
$worknote-orchestrate my-research-task.md
$worknote-orchestrate my-research-task.md status
```

Alternatively, run each request sequentially from the shell. Single quotes keep
`$` literal so the shell does not expand the skill name:

```bash
codex exec '$research-memory init my-research-task.md'
codex exec '$worknote-orchestrate my-research-task.md'
codex exec '$worknote-orchestrate my-research-task.md status'
```

For plugin installs, select the namespaced skills in `/skills` and substitute those
names for the standalone names above. Init creates `my-research-task.memory/`;
orchestration saves evidence there and fills completed placeholders in the worknote.
Keep the session or `codex exec` process running for the experiment. Execution is
subject to the session's permissions; missing resources or choices may require
interactive input. The final `status` request is read-only. The fictional filled
excerpt in the Claude quickstart illustrates the same expected report format.

Typical requests (Claude plugin slash-command examples):

```text
/worknote-orchestrator:research-memory init /path/to/MyStudy.md
/worknote-orchestrator:research-memory link
/worknote-orchestrator:worknote-orchestrate /path/to/MyStudy.md
/worknote-orchestrator:worknote-orchestrate /path/to/MyStudy.md #3
/worknote-orchestrator:worknote-orchestrate /path/to/MyStudy.md status
```

Init creates `MyStudy.memory/` beside the existing worknote. Link connects a workdir's `./research-memory` to that store and excludes the link through git's local info/exclude. A new, unvalidated recipe normally starts with one interactive canary before parallel execution.

## Operating contracts

The worknote contains conclusions; memory holds evidence and execution details. IDs are reserved in task records even for fill-from-data tasks and never reused. Active Attempts hold progress; closed Attempts and completed Outcomes are preserved.

Before changing a marker, the writer verifies its owner, Attempt, task text, and scoped context. Results are saved before publication. Deleted or changed markers invalidate publication intent; they do not prove the underlying jobs stopped. Terminal ledger entries require evidence. Status and memory queries never repair or mutate data.

Workers are optional: when permitted and available, independent computation may run in parallel while the coordinator serializes shared writes. Otherwise the same workflow runs serially with bounded reads. Independent tabs need explicit handoff for overlapping writes. Exact edits and read-back checks reduce errors but provide neither distributed locking nor multi-file atomicity.

Existing commands, marker grammar, store layout, and scanner CLI/JSON remain compatible. Existing stores need no migration; legacy Attempts without ownership snapshots require reconciliation before publication. `complete-report` is an optional source of content-formatting guidance.

## Documentation and validation

Start with [worknote-orchestrate](skills/worknote-orchestrate/SKILL.md) or [research-memory](skills/research-memory/SKILL.md). Each entrypoint links the references needed for a selected operation.

Run deterministic scanner checks with `bash tests/wn-scan/run.sh`. See [mock-memory cases](tests/mock-memory/CASES.md) for isolated agent-executed actions followed by file-state assertions. Fixture setup and assertions do not themselves execute the skill. Use a fresh scratch directory for each case.

Author: Chunwei Yan.

## Lifecycle helper checks

```bash
python3 -B -m unittest discover -s tests/lifecycle -v
```

These regressions cover durable concurrent ID allocation, stale-attempt guards, task/context
changes, and scanner edge cases. See `tests/lifecycle/CASES.md` for agent-executed scenarios.
`wn_scan.py next_id` is a read-only preview; reserve every new ID with `wn_allocate.py`.
Legacy markers remain readable but must be reconciled into a fresh owned attempt before writes.

## Codex packaging checks

```bash
python3 -B -m unittest discover -s tests/codex -v
```

These offline stdlib checks validate both hosts' manifests, the repo marketplace
catalog (`.agents/plugins/marketplace.json`), skill frontmatter, and installer behavior in temporary directories. They
require neither a Codex binary nor network access and never install to your home.
