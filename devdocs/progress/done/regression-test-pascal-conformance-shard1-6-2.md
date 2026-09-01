---
prio: 70
track: P
summary: "RESOLVED — fixed at `f4fb9d31b` (the owner's own `fix(P): generic type constraints are recorded and checked`), six hours after this was filed and before anyone read the ticket. Every FAIL in this shard was `tgenconstraint*(accepted-invalid)`: pxx specialized a generic whose constraint the argument does not satisfy. All of them now reject with a precise diagnostic. Shard verified green at `922dfa971`, binary `0f1d03315f4eaaa7`. Re-laned T->P: the T fallback was wrong here, and that routing defect is argued on chore-t-fpc-conformance-noise-skews-priority."
status: done
---

> **Track T by default: no lane could be inferred** from `tools/run_pascal_conformance.sh`. This is a FALLBACK, not a finding — nothing here says the defect is Track T's, only that the test source did not name an owner. Re-lane it before working it.

> **origin/master has advanced 9 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-pascal-conformance#shard1/6 red at 27424c927b65 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-30T10:24:14Z
- **Test source:** tools/run_pascal_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-pascal-conformance#shard1/6'` at 27424c927b65789f7fa6b6444a6168baf4deed8d

## Range
> **The named sha `27424c927b65` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `27424c927b65`, last good `e46dbffaa80d`, 231 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
t compiled (must be rejected)
FAIL tgenconstraint28.pp — %FAIL test compiled (must be rejected)
FAIL tgenconstraint33.pp — %FAIL test compiled (must be rejected)
SKIP tgenconstraint39.pp — wontfix: dialect-pass — PXX does not enforce generic constraints (compile-time safety net only; runtime semantics well-defined) — not a bug, FPC-strict candidate
FAIL tgenconstraint7.pp — %FAIL test compiled (must be rejected)
SKIP tgeneric103.pp — gap: standalone `generic procedure Test<T>` + specialize; also unit-only compilation
SKIP tgeneric11.pp — gap: objfpc generic/specialize syntax; `specialize TList<_T>` as a param type
SKIP tgeneric66.pp — gap: generic `object` type with nested record
SKIP tgeneric93.pp — gap: {$if declared(TName<,>)} generic-arity form of declared()
SKIP tgeneric99.pp — gap: unit-/class-qualified `specialize` syntax (ugeneric99.specialize TTest<...>)
SKIP tgenfunc1.pp — gap: generic (standalone) functions + inline specialize call expression
SKIP tgenfunc6.pp — gap: delphi-mode generic instance method Add<T>
SKIP tmoperator3.pp — gap: record management operators Initialize/Finalize lifecycle
SKIP tmoperator9.pp — gap: record management operators Initialize/Finalize called for locals
SKIP toperator4.pp — gap: unit-level `operator +` overload on records with real fields
SKIP tprop1.pp — gap: global `property` section in a program (FPC-mode global properties)
SKIP tset2b.pp — gap: explicit enum ordinal values (dA:=8) + {$packset 2} packed-set semantics
SKIP tstatic2.pp — gap: class var with static class property and inherited access
SKIP tstring1.pp — gap: shortstring Insert/Delete/Copy with out-of-range/negative indices crashes
test-pascal-conformance: 56 pass, 6 fail, 25 skip, 5 auto-gated (of 92)
test-pascal-conformance: FAILURES: tgenconstraint11.pp(accepted-invalid) tgenconstraint17.pp(accepted-invalid) tgenconstraint22.pp(accepted-invalid) tgenconstraint28.pp(accepted-invalid) tgenconstraint33.pp(accepted-invalid) tgenconstraint7.pp(accepted-invalid)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## RESOLVED (frankZ, plexus, 2026-09-02) — the owner fixed it the same day

**Binary `0f1d03315f4eaaa7`, commit `922dfa971`, corpus `fpc-testsuite @
0d122c49534b48`.** Fetched today; this box had no FPC suite, which is why the
first pass at these four could only hypothesise.

Every FAIL row in this shard is `(accepted-invalid)` — the `%FAIL` directive
says the program must be REJECTED and pxx compiled it. All of them are one
construct: **a generic specialized with a type argument that does not satisfy
the declared constraint**, from `ugenconstraints.pas`'s `TTest1<T: class>`,
`TTest2<T: record>`, `TTest3<T: TTestClass>`, `TTest7<T: ITest1>` and friends.
pxx parsed the constraint clause and then ignored it.

`f4fb9d31b fix(P): generic type constraints are recorded and checked`
(yoctobyte, 2026-08-30 15:56Z) implements the check. This shard was filed at
`27424c927b65`, **09:59Z the same day** — `git merge-base --is-ancestor
f4fb9d31b 27424c927b65` is false, so the ticket was already stale six hours
after it was written and stayed open for three days.

Measured directly at HEAD, all nineteen `(accepted-invalid)` rows across shards
1/2/3, one compile each:

```
pascal26:12: error: generic constraint violated: TTest2<T> is constrained to `record`, but ...
pascal26:12: error: generic constraint violated: TTest15<T> is constrained to `ITest2`, but ...
pascal26:12: error: generic constraint violated: TTest17<T1> is constrained to `ITest1`, but ...
```

**All six shards green, one run, tree provably unchanged across it:**

```
shard 0/6   62 pass, 0 fail, 25 skip, 5 auto-gated (of 92)
shard 1/6   63 pass, 0 fail, 24 skip, 5 auto-gated (of 92)
shard 2/6   50 pass, 0 fail, 36 skip, 6 auto-gated (of 92)
shard 3/6   57 pass, 0 fail, 29 skip, 6 auto-gated (of 92)
shard 4/6   61 pass, 0 fail, 25 skip, 5 auto-gated (of 91)
shard 5/6   56 pass, 0 fail, 28 skip, 7 auto-gated (of 91)
HEAD_BEFORE = 922dfa971e21c7e0...
HEAD_AFTER  = 922dfa971e21c7e0...    (recorded, not assumed)
```

349 pass is the positive control: 0 fail out of a shard that ran nothing would
read identically, and these same shards reported FAILs from this same runner
three days ago, so the failing population is reachable.

## Three skip rows went false and nobody re-read them

The same fix silently invalidated three rows of `test/pascal-conformance/pxx.skip`,
removed in this commit:

- `tgenconstraint38.pp` and `tgenconstraint39.pp` — `wontfix: dialect-pass — PXX
  does not enforce generic constraints ... not a bug, FPC-strict candidate`.
  That sentence stopped being true at `f4fb9d31b`. Both reject correctly now.
- `tgenconstraint1.pp` — `gap: Delphi generic constraint syntax`. It compiles
  clean.

A skip row is a capability claim about the compiler that the runner obeys and
nothing re-checks. **The name is not the thing**, in a file whose whole job is
names. `tgenconstraint37.pp` keeps its `gap:` row — it is real
(`expected 'end' before ';'` on a forward-declared class/interface used as a
constraint) and it is the only surviving one.

## The routing, which is the part worth keeping

This ticket carried `track: T` at prio 70 for three days because the failing
step named `tools/run_pascal_conformance.sh` and the filer fell back to the
script's lane. **T owns the tool, never the bug.** The defect was Track P's from
the first line and the owner fixed it in Track P without a ticket.

The filer does not have to guess: the runner already prints the failure KIND —
`(compile)` versus `(accepted-invalid)` — and `--report` already tags each test
`gap:` / `wontfix:` / `untriaged`. `(compile)` on an untriaged test is a candidate
gap and belongs low; `(accepted-invalid)` means the compiler accepts a program it
can already tell is wrong. Argued in full on
[[chore-t-fpc-conformance-noise-skews-priority]], where the measured
disagreement with the pin-allowlist option also lives.
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
