---
track: T
prio: 30
type: bug
blocked-by: []
summary: "`tools/fuzz.sh` compares the RUNNER's crash text along with the program's output, so a mutant that segfaults identically on all four targets is reported as three DIVERGENCEs — native says \"timeout: the monitored command dumped core\", qemu says \"uncaught target signal 11\". Same output, same exit code, different reporter."
status: done
---

# fuzz.sh reports an identical crash on every target as a divergence

- **Type:** bug (false positive in a fuzz oracle) — **Track T** (`tools/fuzz.sh`).
- **Found:** 2026-08-16 by the Track A+C+P+N session, running an 18-minute
  cross-target sweep over its own backend changes. T owns the tool; the finding
  is filed, not fixed here.

## Measured

One finding in 18 minutes, reported three times (once per cross target):

```
DIVERGENCE: seed=test/test_cross_shortcircuit.pas trial=13 arch=i386
  native: EXIT:139 OUT:and-false calls=0 … or-false calls=2
          timeout: the monitored command dumped core
  i386:   EXIT:139 OUT:and-false calls=0 … or-false calls=2
          Segmentation fault (core dumped)
```

The exit code is 139 on both. The program's own six lines of output are
identical on both. What differs is the last line — which is not the program
speaking, it is `timeout` on native and qemu/the shell on the cross target,
reporting the same crash in their own words.

## Why it matters more than one false positive

A fuzzer's whole value is that a report means something. This one fires on
**every crashing mutant**, and a crashing mutant is common (the mutations are
textual, so a nil deref is one edit away) — so the noise scales with the run
length, exactly like the `shl` blind spot did before
[[bug-t-fpc-probe-reports-the-deliberate-shl-deviation-as-new]]. It also
inverts the tool's purpose: an identical crash on all four targets is the
*strongest* evidence of NO backend divergence, and it is being reported as
divergence.

## Suggested fix

Compare the program's stdout only, and compare the exit code separately —
the crash text arrives on stderr, from a process that is not the program. If
stderr is wanted for triage, keep it in the finding's write-up rather than in
the comparison key. A cheap equivalent: when the exit codes match AND both are
a signal death, require the stdout to differ before reporting.

Worth a second look while there: a mutant that crashes on every target is
itself uninteresting (the mutation broke the program), so it may deserve the
same "expected/uninteresting, skipped not reported" treatment the harness
already gives compile failures.

## What the run otherwise found

Nothing — which is the useful half. 18 minutes of mutation + cross-target
differential over the `test_cross_*` seed pool, against a compiler carrying
that session's multi-dim array and pointer-stride changes, produced no real
codegen divergence.

## Fixed 2026-08-19 by Track T (plexus-T)

Confirmed still live before touching it: `run_target_capture` captured with
`2>&1` on both arms, so the reaper's words were in the comparison key.

**The script's own header has always specified the right behaviour** — *"runs
all four, and diffs stdout+exit code"*. The `2>&1` was drift from the documented
contract, not a considered choice, which is why the fix needs no argument about
what the key should be.

- stderr is captured to a per-arch file and kept OUT of the key; the finding
  write-up still carries it, explicitly labelled as triage-only.
- The suggested extra treatment — skip a mutant that crashes on every target the
  way a native `<TIMEOUT>` is skipped — was **deliberately not taken**. With
  stdout-only comparison the uninteresting case already reports nothing, while a
  native crash against a cross target that produces real output stays visible.
  Skipping crashers wholesale would discard that, and it is a genuine divergence
  shape.

**Gate:** `tools/fuzz_compare_key_devtest.py` (new). It drives the real
`fuzz.sh` against a fake ROOT — stub compiler, stub cross-runner, one seed — and
asserts both halves:

- identical stdout and exit, different reaper stderr → no divergence, nothing
  saved;
- genuinely different stdout → still reported, mutant still saved.

The second is the one that matters: a false positive is trivial to "fix" by
breaking detection. There is a third check for the same reason — the stub
compiler counts its invocations, so a run that compiled nothing cannot pass the
clean case vacuously.

Verified the devtest FAILS on the unfixed script (3 checks) and passes on the
fixed one.

## Log
- 2026-08-19 — resolved, commit PENDING-COMMIT.
