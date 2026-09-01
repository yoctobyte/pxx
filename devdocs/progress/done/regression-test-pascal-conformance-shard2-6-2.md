---
prio: 70
track: P
summary: "RESOLVED — fixed at `f4fb9d31b` (the owner's own `fix(P): generic type constraints are recorded and checked`), six hours after this was filed and before anyone read the ticket. Every FAIL in this shard was `tgenconstraint*(accepted-invalid)`: pxx specialized a generic whose constraint the argument does not satisfy. All of them now reject with a precise diagnostic. Shard verified green at `922dfa971`, binary `0f1d03315f4eaaa7`. Re-laned T->P: the T fallback was wrong here, and that routing defect is argued on chore-t-fpc-conformance-noise-skews-priority."
status: done
---

> **Track T by default: no lane could be inferred** from `tools/run_pascal_conformance.sh`. This is a FALLBACK, not a finding — nothing here says the defect is Track T's, only that the test source did not name an owner. Re-lane it before working it.

> **origin/master has advanced 9 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-pascal-conformance#shard2/6 red at 27424c927b65 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-30T10:24:14Z
- **Test source:** tools/run_pascal_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-pascal-conformance#shard2/6'` at 27424c927b65789f7fa6b6444a6168baf4deed8d

## Range
> **The named sha `27424c927b65` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `27424c927b65`, last good `e46dbffaa80d`, 231 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Of/local types inside generic routines)
SKIP tgenfunc15.pp — gap: generic array type templates + generic method overloads with array-of-T params
SKIP tgenfunc23.pp — gap: generic procedure overload on T vs array of T + inline specialize call
SKIP tgenfunc7.pp — gap: generic functions/methods imported from another unit and specialized
SKIP tinterface6.pp — gap: interface GUID/CORBA-UID usable as a typed constant (tguid/shortstring init)
SKIP tmoperator4.pp — gap: management operators across multiple record types
SKIP tobject6.pp — gap: `object` type with nested type/class var/const sections and class property
SKIP toperator3.pp — gap: unit-level `operator +` overload on records, mutually-used units
SKIP toperator78.pp — gap: global operator overloads on primitive/set types (**, ><, div, mod, and)
SKIP toperator89.pp — gap: overloading implicit assignment operator `:=` (global operator)
SKIP toperator94.pp — gap: objfpc `class operator :=` implicit conversion to shortstring types — the duplicate-conversion check (parser.inc ~1860) falsely collides distinct frozen-string result kinds; root is the same String[N] tk inconsistency (tyString vs tyFixedString vs tyShortString) that toperator93 exposed at the use site
SKIP tover3.pp — wontfix: dialect-pass — overload ambiguity — PXX deterministically ranks (picks longint for cardinal arg) by design; FPC-parity ambiguity errors belong to --strict-overload
SKIP tset2c.pp — gap: explicit enum ordinal values (dA:=17) + {$packset 1} packed-set semantics
SKIP tstring2.pp — gap: RTL `ExitCode` variable missing (needed by erroru unit); char-array to shortstring assign
test-pascal-conformance: 43 pass, 7 fail, 36 skip, 6 auto-gated (of 92)
test-pascal-conformance: FAILURES: tgenconstraint12.pp(accepted-invalid) tgenconstraint18.pp(accepted-invalid) tgenconstraint23.pp(accepted-invalid) tgenconstraint29.pp(accepted-invalid) tgenconstraint34.pp(accepted-invalid) tgenconstraint3.pp(accepted-invalid) tgenconstraint8.pp(accepted-invalid)

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
