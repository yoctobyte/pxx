---
prio: 70
---

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-pascal-conformance#shard0/6 red at 98ed38202254 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-22T00:45:59Z
- **Test source:** tools/run_pascal_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-pascal-conformance#shard0/6'` at 98ed382022547bbe6624c779ee024a3ad1dea518

## Range
bad `98ed38202254`, last good `23becd24b8e5`, 423 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL tgeneric70.pp — compile error:
pascal26:11: error: generic specialization nested deeper than 16 levels (or a rewrite loop)
(tail)
ting from specialize of another generic
SKIP tgeneric21.pp — gap: accepts-invalid — nested generic-in-generic declaration — semantics unverified, real gap (see bug-pascal-missing-diagnostics-fail-tests triage 2026-07-11)
SKIP tgeneric27.pp — gap: enum-tagged variant part with INLINE enum type in a template's record element (`case enum:(one,two) of`)
SKIP tgeneric5.pp — gap: objfpc generic syntax + `typeinfo(_T)` intrinsic and typinfo unit
SKIP tgeneric65.pp — gap: generic record with nested `object` type
FAIL tgeneric70.pp — compile error:
    pascal26:11: error: generic specialization nested deeper than 16 levels (or a rewrite loop)
      near: type TSomeGeneric  T   >>> class end  
SKIP tgeneric76.pp — gap: generic record with static class methods + specialized aliases (TPointEx<T>) unsupported
SKIP tgeneric92.pp — gap: objfpc generic syntax + `with` over a generic type parameter record
SKIP tgenfunc19.pp — gap: generic global function + class helper method resolution via specialize
SKIP tgenfunc5.pp — gap: generic instance methods (objfpc generic function ... <T>)
SKIP tinterface4.pp — wontfix: needs FPC's `variants` unit and FPC's IInterface/NewInstance refcount internals
SKIP tmoperator2.pp — gap: record Initialize/Finalize management operators with managed fields
SKIP tmoperator8.pp — gap: management operators AddRef/Copy/Initialize/Finalize on records
SKIP tobject4.pp — gap: direct destructor call as a statement (`o1.destroy;`) not parsed
SKIP tover1.pp — gap: overload resolution across shortstring/ansistring/widestring/pchar params
SKIP tprocvar3.pp — gap: delphi-mode procvar of object, @-less proc assignment, codepointer method addresses
SKIP tset2a.pp — gap: explicit enum ordinal values (dA:=8) + {$packset 1} packed-set semantics
SKIP tstring11.pp — gap: overload resolution RawByteString vs UnicodeString (char/array/pchar args)
test-pascal-conformance: 56 pass, 1 fail, 30 skip, 5 auto-gated (of 92)
test-pascal-conformance: FAILURES: tgeneric70.pp(compile)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-22 — auto-closed by the plexus watcher: `test-pascal-conformance#shard0/6` passes at fd93e4a71c37 (tier full); it was red at 5179c4d4350b. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
