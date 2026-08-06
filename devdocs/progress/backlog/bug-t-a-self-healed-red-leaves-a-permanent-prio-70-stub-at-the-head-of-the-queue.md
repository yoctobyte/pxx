---
track: T
prio: 60
type: bug
summary: "twatch files a prio-70 stub on NEW-RED but never closes or annotates it when a later report moves the same job to FIXED, so a self-healing red outranks all real work indefinitely."
---

# A self-healed red leaves a permanent prio-70 stub at the head of the ranked queue

- **Track:** T (tools & testing). Files: `tools/twatch.py` (the stub-filing path).
- **Found:** 2026-08-06, working the N queue — the top TWO items by effective
  priority were both already-fixed reds.

## What happens

`twatch` auto-files a stub ticket into `devdocs/progress/backlog/` on NEW-RED,
with `prio: 70`. That is the right call: a fresh regression should outrank
feature work. But nothing ever takes it back. When a later report moves the same
job to **FIXED**, the stub is not closed, not annotated, not even re-prioritised.

Because 70 is above almost everything else in the backlog, and because
`tools/progress.sh next` ranks by effective priority, a red that healed on its
own **permanently occupies the head of the queue** and is handed to the next
agent that asks for work.

## Measured

Nine open auto-filed stubs on 2026-08-06. **All nine passed at HEAD** (`733be3321`,
compiler snapshot sha256 `cafd50517875`), each run with its own stub's repro line:

| stub's test | watcher trail |
| --- | --- |
| `test_cpyext_hello` | NEW-RED `34c41bd` → FIXED `aba953c` (~1h) |
| `test_cpyext_args_errors` | NEW-RED `34c41bd` → FIXED `aba953c` |
| `test_cpyext_containers` | NEW-RED `34c41bd` → FIXED `aba953c` |
| `test_cpyext_cython` | NEW-RED `34c41bd` → FIXED `aba953c` |
| `test_cpyext_markupsafe` | NEW-RED `34c41bd` → FIXED `aba953c` |
| `test_nilpy_dotted_package_import` | NEW-RED `34c41bd` → FIXED `aba953c` |
| `test_nilpy_qualifier_vs_cproc` | NEW-RED `34c41bd` → FIXED `8b9d08b` (~15min) |
| `test_nilpy_pyexpr_semantics` | NEW-RED `9294bce` → STILL-RED ×8 → FIXED `733be33` |
| `test_nilpy_augmented_assign_class_dunder` | NEW-RED `e8450c5` → STILL-RED ×18 → FIXED `733be33` |

The last two rows are the *healthy* case — a genuine regression, correctly
tracked STILL-RED across every report until a fix landed. Note the watcher
**does** know the answer: `FIXED` is a section it already emits. The gap is only
that the stub is not wired to it.

The six `34c41bd` rows are the pathology: they had been stale for a day, and
seven of the nine stubs were pure queue noise.

Second, smaller finding: `test_nilpy_augmented_assign_class_dunder` had **two**
stubs filed for it, one from the `test-core` job and one from `test-nilpy`, since
the same source is exercised by both. Whatever closes stubs should key on the
job, but dedupe by test source when filing.

## Suggested fix

In the same pass that emits the `## FIXED` section, for each job listed there:
resolve its stub if one is open — or, if closing from the watcher identity is
outside its write scope (face 1 writes ONLY `tstate/`, which is the rule and
should stay), then at minimum append a `FIXED at <sha>` line to the stub and drop
its `prio:` well below 70, and let face 2 do the actual close. Either way the
ranked queue stops advertising fixed work as the most urgent thing in the repo.

Worth considering: a `--tier` / `progress.sh check` assertion that no open
auto-filed stub's job is currently green, so this class of drift is caught by the
gate rather than by an agent noticing it manually.

## Gate
`tools/testmgr.py --tier full` green (T's own gate), plus a scratch bare repo
exercising the file→heal→close cycle end to end. Test the tooling with QUICK
tiers, never long runs.
