---
prio: 70
track: T
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
