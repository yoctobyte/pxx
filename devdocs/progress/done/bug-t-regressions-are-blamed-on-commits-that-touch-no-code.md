---
track: T
prio: 50
type: bug
summary: "Nine open regressions in tstate name a `bad=` commit that changes only tstate/ or a progress .md. A docs commit cannot break test-c-conformance-arm32, so either the blame step is landing on a no-op or the failures are flaky and the bisect converged on noise. Either way the reports point Track A at the wrong place."
status: done
owner: pxx-aa
---

# tstate blames regressions on commits that touch no compiler code

- **Type:** bug (Track T tooling / report quality)
- **Opened:** 2026-08-21 by the Track A session, from `tools/twatch.py --status`
  on plexus at HEAD `f81f03c51`.
- **Filed by A, owned by T** — "T owns the tool, never the bug", and its mirror:
  a defect in T's own tooling is T's.

## Evidence

Two clusters, nine open regressions between them, and both `bad=` shas change
nothing a compiler could notice.

```
open regression: test-c-conformance-arm32#shard1/6      bad=1b9b43e5b511 (132 in range)
open regression: test-c-conformance-riscv32#shard1/6    bad=1b9b43e5b511 (132 in range)
open regression: test-nilpy#src:test/test_nilpy_callable_to_str_param_fails.npy
                                                        bad=1b9b43e5b511 (132 in range)
open regression: test-pascal-conformance#shard4/6       bad=1b9b43e5b511 (132 in range)
open regression: tools-devtest#00                       bad=1b9b43e5b511 (132 in range)
open regression: test-nilpy#src:test/test_pascal_at_procvar_mode.pas@1    bad=23becd24b8e5
open regression: test-nilpy#src:test/test_pascal_mode_switch_cli.pas@2    bad=23becd24b8e5
open regression: test-nilpy#src:test/test_pascal_self_result_delphi.pas@1 bad=23becd24b8e5
open regression: test-nilpy#src:test/test_pascal_self_result_delphi.pas@2 bad=23becd24b8e5
```

```
$ git show -s --stat 1b9b43e5b511
1b9b43e5b tstate(plexus): 4a12acf6e7f0 GREEN (native)
 devdocs/progress/tstate/TSTATE.md          |  2 +-
 devdocs/progress/tstate/plexus.json        | 24 +++++++++++-----------
 devdocs/progress/tstate/runs-plexus.ndjson |  1 +

$ git show -s --stat 23becd24b8e5
23becd24b docs(progress): record the shas the resolves landed as
 ...concat-leaks-on-every-cross-target.md | 2 +-
```

The first is **the watcher's own tstate publish commit**. The second is a
one-line edit to a resolved ticket's front matter. Neither can change
`test-c-conformance-arm32`.

## Why it matters

These reports are the *only* thing a dev lane sees of the breadth matrix, and
the per-fix loop is built on trusting them (CLAUDE.md: "breadth is Track T's
job ... it comes back asynchronously as tstate reports and tickets"). A `bad=`
sha that points at a docs commit costs a lane the exact thing the report was
supposed to save: it has to go re-derive the range by hand. The Track A session
that hit the second cluster re-ran all four commands at HEAD and every one
produced its expected output, so it wrote them off as stale — which is the
right call for these and the wrong habit to build.

## Two candidate causes, and they need telling apart before anything is fixed

1. **The blame step lands on a no-op.** With `132 in range` the bisect had a
   wide window; if it can select a commit that touches no build input, either it
   is not skipping doc-only commits or it is picking a boundary rather than a
   culprit. A commit whose diff touches neither `compiler/**`, `lib/**`,
   `tools/**` nor `test/**` cannot be the first bad one, and saying so is cheap.
2. **The failures are FLAKY and the bisect converged on noise.** A test that
   fails intermittently makes every bisect answer arbitrary, and an arbitrary
   answer lands on a docs commit as readily as any other. If that is it, the fix
   is not in the blame step at all — it is confirming a red before spending a
   bisect on it.

Measure, do not reason (`devdocs/dev/debugging-playbook.md`): re-run one of the
five `1b9b43e5b511` jobs at that sha and at its parent several times each. Same
verdict every time -> cause 1. Verdict varies -> cause 2.

## Suggested scope

- Refuse to attribute a regression to a commit with no build-input diff; walk to
  the nearest commit that has one and say in the report that it did.
- Re-confirm a red before opening a bisect, and record the confirmation count in
  the report so a dev lane can see whether a finding is solid or a coin flip.
- Surface `(N in range)` more loudly when N is large: 132 is not a bisect
  result, it is an unnarrowed window, and it should not read like an answer.

## Second sighting — 2026-08-21 (agent-A)

Four more, and this time the mechanism is visible in tstate's own header. The
jobs

  test-nilpy#src:test/test_pascal_at_procvar_mode.pas@1
  test-nilpy#src:test/test_pascal_mode_switch_cli.pas@2
  test-nilpy#src:test/test_pascal_self_result_delphi.pas@1
  test-nilpy#src:test/test_pascal_self_result_delphi.pas@2

all went red together at `23becd24b8e5` -- a one-line ticket edit -- and all four
pass at HEAD when re-run one at a time (verified expectation by expectation,
both dialect modes, at 2c2ba74e40fa).

The header line for that run reads `full through 23becd24b8e5 RED ... 3600.3s`.
**3600.3 seconds is the hour wall, not a duration.** So the run did not finish;
it was cut off, and every source the cut-off job owned was recorded as failing
with the blame on whatever sha was under test. That is the same shape as the
first sighting, with the cause now named: a job that dies at the wall is
indistinguishable, in the published report, from a job whose tests failed.

Worth fixing at the source: a run that hits its wall should publish TIMEOUT (or
publish nothing) for the jobs it did not finish, never RED. A RED that is really
"the box was busy" costs a dev agent a full triage cycle each time it reaches the
top of the ranked queue -- four tickets at prio 70 this time -- and it trains
everyone to distrust the queue, which is the expensive part.

## Log
- 2026-08-26 — resolved, commit 27ae5cc11.

## Resolved 2026-08-26 (pxx-aa, Track T)

This is a fifth report of one root cause — *the blame is computed from what
changed, without asking whether the job could see it* — see
[[bug-t-a-blame-range-is-computed-from-what-changed-not-from-what-the-job-can-see]].
Two of its faces were already fixed and cover the **range** half of this
ticket's evidence: the wrong anchor (`c68e6492e`) and untestable commits inside
the range (`cf7d805d4`, which is literally this ticket's "132 in range" number).

What remained was the **`bad=` sha** half, and it was not a computation bug at
all. `bad` is the sha that was TESTED. The watcher tests whatever HEAD is, and
HEAD is very often its own tstate publish commit — so `bad` is regularly a
commit that changes four `.md` files. Leaving `bad` as observed is right: it is
where the red was seen, and rewriting it would falsify the ledger. Publishing it
as a *lead* without saying what it is, is the defect.

`cascade_range_note()` has said the true thing for a while:

> **The named sha CANNOT be the cause** — it touches no buildable file. It is
> the sha that was TESTED, i.e. the upper bound of an untested range.

and the **ordinary** path, where nearly every regression goes, could not reach
that sentence. Same shape as every other face: the right answer existed on one
path only. It is now a banner prefixed to all five range shapes, guarded by a
test that asserts it reaches every one (a banner reaching four of five is this
bug again, one path along).

**Recomputed each pass, never cached.** The answer depends on
`NOTEST_PREFIXES`, so a stamp written once and read forever would be the same
one-way trap as a boolean repair flag, only quieter. One `git diff-tree` per
open regression per idle pass is nothing.

Verified against both regressions on the board right now — including
`ab584382edcd`, the 250-line `prio:` frontmatter commit that was named as
culprit for four unrelated jobs, and `fd93e4a71c37`, a tstate publish commit:

```
> **The named sha `ab584382edcd` CANNOT be the cause** — it touches no buildable
> file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the
> upper bound of an untested range; the cause is somewhere below it.
```
