---
prio: 70
track: T
---

> **Track T by default: no lane could be inferred** from `tools/run_pascal_conformance.sh`. This is a FALLBACK, not a finding — nothing here says the defect is Track T's, only that the test source did not name an owner. Re-lane it before working it.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-pascal-conformance#shard0/6 red at f6303d410d78 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T09:10:29Z
- **Test source:** tools/run_pascal_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-pascal-conformance#shard0/6'` at f6303d410d783b2cbfad4ba500bf86bfa1a53b6d

## Range
> **The named sha `f6303d410d78` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `f6303d410d78`, last good `90501813d990`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
eclared in another unit (inline class funcs)
SKIP tgeneric10.pp — gap: objfpc generic/specialize syntax + nested type (TCompareFunc) of a specialization
SKIP tgeneric16.pp — gap: generic class inheriting from specialize of another generic
SKIP tgeneric21.pp — gap: accepts-invalid — nested generic-in-generic declaration — semantics unverified, real gap (see bug-pascal-missing-diagnostics-fail-tests triage 2026-07-11)
SKIP tgeneric5.pp — gap: objfpc generic syntax + `typeinfo(_T)` intrinsic and typinfo unit
SKIP tgeneric65.pp — gap: generic record with nested `object` type
SKIP tgeneric76.pp — gap: generic record with static class methods + specialized aliases (TPointEx<T>) unsupported
SKIP tgeneric92.pp — gap: objfpc generic syntax + `with` over a generic type parameter record
SKIP tgenfunc19.pp — gap: generic global function + class helper method resolution via specialize
SKIP tgenfunc5.pp — gap: generic instance methods (objfpc generic function ... <T>)
SKIP tinterface4.pp — wontfix: needs FPC's `variants` unit and FPC's IInterface/NewInstance refcount internals
SKIP tmoperator2.pp — gap: record Initialize/Finalize management operators with managed fields
SKIP tmoperator8.pp — gap: management operators AddRef/Copy/Initialize/Finalize on records
SKIP tover1.pp — gap: overload resolution across shortstring/ansistring/widestring/pchar params
SKIP tprocvar3.pp — gap: delphi-mode procvar of object, @-less proc assignment, codepointer method addresses
SKIP tset2a.pp — gap: explicit enum ordinal values (dA:=8) + {$packset 1} packed-set semantics
SKIP tstring11.pp — gap: overload resolution RawByteString vs UnicodeString (char/array/pchar args)
test-pascal-conformance: 55 pass, 6 fail, 26 skip, 5 auto-gated (of 92)
test-pascal-conformance: FAILURES: tgenconstraint10.pp(accepted-invalid) tgenconstraint16.pp(accepted-invalid) tgenconstraint21.pp(accepted-invalid) tgenconstraint27.pp(accepted-invalid) tgenconstraint32.pp(accepted-invalid) tgenconstraint6.pp(accepted-invalid)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
