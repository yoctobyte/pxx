---
prio: 70
track: T
---

> **Track T by default: no lane could be inferred** from `tools/run_pascal_conformance.sh`. This is a FALLBACK, not a finding — nothing here says the defect is Track T's, only that the test source did not name an owner. Re-lane it before working it.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-pascal-conformance#shard1/6 red at f6303d410d78 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T09:10:29Z
- **Test source:** tools/run_pascal_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-pascal-conformance#shard1/6'` at f6303d410d783b2cbfad4ba500bf86bfa1a53b6d

## Range
> **The named sha `f6303d410d78` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `f6303d410d78`, last good `90501813d990`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

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
