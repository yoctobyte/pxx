---
prio: 70
track: T
---

> **Track T by default: no lane could be inferred** from `tools/run_pascal_conformance.sh`. This is a FALLBACK, not a finding — nothing here says the defect is Track T's, only that the test source did not name an owner. Re-lane it before working it.

> **origin/master has advanced 9 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-pascal-conformance#shard4/6 red at 27424c927b65 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-30T10:24:14Z
- **Test source:** tools/run_pascal_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-pascal-conformance#shard4/6'` at 27424c927b65789f7fa6b6444a6168baf4deed8d

## Range
> **The named sha `27424c927b65` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `27424c927b65`, last good `e46dbffaa80d`, 231 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
eader says %fail is an FPC IMPLEMENTATION limitation ("assembler symbols not global"), not a language rule — PXX passing is correct
SKIP tgeneric1.pp — gap: objfpc `generic TList<_T> = class` / `specialize` syntax not parsed
SKIP tgeneric30.pp — wontfix: dialect-pass — mode-delphi generic method impl without <T> — PXX's Delphi-generics rewriter deliberately accepts the bare name (3d71edcf); not a bug
SKIP tgeneric7.pp — gap: generics across units + $R range-check state per unit (expects runtime error 201)
SKIP tgeneric85.pp — gap: accepts-invalid — invalid generic record body accepted (pre-specialization checking)
SKIP tgenfunc3.pp — gap: generic class functions (generic class function Add<T>) not supported
SKIP tgenfunc9.pp — gap: generic methods with private/protected visibility specialized from caller
SKIP tobject2.pp — gap: old-style `object` types with virtual methods, constructor/destructor
SKIP toperator1.pp — gap: operator overloading (+) on records declared in units; cross-unit operator resolution
SKIP toperator9.pp — gap: operator overload for `in` on a record type not supported by the parser
SKIP tprocvar1.pp — gap: old-style `object` types with constructor/virtual methods (same gap as tobject2.pp / tsealed6.pp). Its procvar content passes now — the previous reason named three gaps (method pointers, @Class.Method, typed-const procvars) and a fourth found chasing it (anonymous procedural types); all are fixed, and unskipping shows `object constructor init` is what is left.
SKIP tsealed6.pp — gap: `object abstract` / `object sealed` modifiers in object declarations
SKIP tstring4.pp — wontfix: reads ansistring refcount/length header words — FPC internal string layout
test-pascal-conformance: 55 pass, 5 fail, 26 skip, 5 auto-gated (of 91)
test-pascal-conformance: FAILURES: tgenconstraint14.pp(accepted-invalid) tgenconstraint25.pp(accepted-invalid) tgenconstraint30.pp(accepted-invalid) tgenconstraint36.pp(accepted-invalid) tgenconstraint4.pp(accepted-invalid)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
