---
prio: 60
---

# pasmith emits order-dependent programs, and its printed repro line does not reproduce

- **Type:** bug (fuzzer correctness — two defects, both found while clustering the corpus)
- **Track:** T — tools & testing (T owns the TOOL; neither of these is a compiler bug)
- **Status:** done
  [[bug-pascal-case-selector-multiple-evaluation]].

## Defect 1 — the `repro:` line in every report is INCOMPLETE, so it does not reproduce

Reports print:

```
repro: tools/pasmith.py --seed N --vars 10 --funcs 3 --stmts 20 --depth 3
```

but `twatch.py` actually launches the fuzzer with `--classes 4 --strs 3` as well. Running
the printed line generates a **different program**, which does not diverge — so anyone
triaging a report by hand concludes "cannot reproduce" and the finding is discarded.

The working line is:

```
tools/pasmith.py --seed N --vars 10 --funcs 3 --stmts 20 --depth 3 --classes 4 --objs 3 --strs 3
```

`pasmith_run.py` builds the repro string and omits `--classes/--objs/--strs`. One-line fix:
print the ACTUAL argv it ran with, never a hand-written subset. A repro line that does not
reproduce is worse than no repro line.

## Defect 2 — the generator emits programs whose result depends on evaluation ORDER

~3% of the divergences (3 of a 40-seed sample: 3384, 7704, 9565) are not compiler bugs. The
generator puts **two side-effecting calls in one argument list / operand pair**:

```pascal
g7 := SafeMod_qword(qword(not f1(g14)), qword(g7 and f0(g6, g6)));
```

Pascal leaves argument evaluation order **unspecified**. pxx evaluates call arguments
left-to-right, FPC right-to-left; both are legal. Since every generated function calls the
checksum `Mix()`, the two orders produce the same multiset of mixed values in a different
ORDER, and the checksum differs.

This is category (a) in the fuzzer's own report note ("pasmith emitted UB/impl-defined
code"). Filing it against Track A would be wrong.

Fix options (pick one):
- never place more than one side-effecting call in a single argument list / binary operand
  pair (hoist one into a temp statement); or
- make `Mix` order-insensitive (sum/xor rather than a position-dependent hash) — cheaper,
  but it weakens the oracle everywhere else, so the hoist is preferred.

## Why both matter more than they look
Together they set the false-signal rate of the whole fuzzing lane: defect 2 manufactures
divergences that are not bugs, and defect 1 makes every report — real or not — unverifiable
by hand.

## Gate
`tools/testmgr.py --tier full` green; a report's printed repro line, pasted verbatim,
reproduces the divergence.

## Defect 3 (found while fixing 1 and 2) — the fuzzer tested the PINNED binary, not the sha

`pasmith_run.py` defaulted its compiler to `PXX_STABLE` = `stable_linux_amd64/default/pinned`
— the committed pin, which lags HEAD by however many commits. So the idle fuzz slice ran
against a compiler from long before the sha it stamped on every finding. Two consequences:

- **Findings were misattributed.** The bug is not in the sha under test; it is in whatever
  the pin was built from.
- **An already-fixed bug re-reports forever**, until someone happens to re-pin. This is
  exactly what happened: all ~70 published divergences were
  [[bug-pascal-case-selector-multiple-evaluation]] (b346), which Track A had **already
  fixed at HEAD** — the fuzzer kept re-finding it because the *pin* still had it.

Proof: the 81 seeds that diverged against the pin give **0 divergences** against the
compiler built at HEAD.

Fix: prefer the locally built `compiler/pascal26` (what testmgr built at this sha); fall
back to the pin only when there is no local build; `PXX_STABLE` still overrides for
deliberately fuzzing the pin. Every report now records `compiler=<path>` — a finding that
does not say which binary produced it cannot be attributed at all.

## Resolution (2026-07-14)
All three defects fixed.
- **1 (repro line):** `pasmith_run` now derives the repro string from the SAME argv list it
  generates with, so the two cannot drift. Verified: a published finding's line, pasted
  verbatim, reproduces the divergence.
- **2 (order dependence):** at most ONE side-effecting call per expression tree (the
  counter resets per statement — Pascal specifies statement order, not evaluation order
  within an expression). Keeps side-effecting functions in the corpus, which "make them
  pure" would have thrown away. Verified: 0 statements with >1 call across a sample.
- **3 (stale compiler):** fuzz the compiler at this commit; record it in every report.

## Log
- 2026-07-14 — resolved, commit HEAD.
