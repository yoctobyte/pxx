---
prio: 70
---

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-pascal-conformance#shard4/6 red at 61e2448bac6d (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-18T04:23:41Z
- **Test source:** tools/run_pascal_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-pascal-conformance#shard4/6'` at 61e2448bac6d3f61657fb54a746d3e33d2ad96fc

## Range
bad `61e2448bac6d`, last good `e0f6748717e6`, 12 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL tset2.pp — compile error:
pascal26:161: error: invalid optional IR node reference in block first
FAIL tset7.pp — compile error:
pascal26:36: error: invalid optional IR node reference in block first
(tail)
 FPC IMPLEMENTATION limitation ("assembler symbols not global"), not a language rule — PXX passing is correct
SKIP tgeneric1.pp — gap: objfpc `generic TList<_T> = class` / `specialize` syntax not parsed
SKIP tgeneric30.pp — wontfix: dialect-pass — mode-delphi generic method impl without <T> — PXX's Delphi-generics rewriter deliberately accepts the bare name (3d71edcf); not a bug
SKIP tgeneric63.pp — gap: generic record with nested record type
SKIP tgeneric7.pp — gap: generics across units + $R range-check state per unit (expects runtime error 201)
SKIP tgeneric85.pp — gap: accepts-invalid — invalid generic record body accepted (pre-specialization checking)
SKIP tgenfunc3.pp — gap: generic class functions (generic class function Add<T>) not supported
SKIP tgenfunc9.pp — gap: generic methods with private/protected visibility specialized from caller
SKIP tmoperator11.pp — gap: management operator class operator Initialize on records
SKIP tobject2.pp — gap: old-style `object` types with virtual methods, constructor/destructor
SKIP toperator1.pp — gap: operator overloading (+) on records declared in units; cross-unit operator resolution
SKIP toperator9.pp — gap: operator overload for `in` on a record type not supported by the parser
SKIP tprocvar1.pp — gap: method pointers (`procedure(l:longint) of object`), @Class.Method, typed-const procvars
SKIP tsealed6.pp — gap: `object abstract` / `object sealed` modifiers in object declarations
FAIL tset2.pp — compile error:
    pascal26:161: error: invalid optional IR node reference in block first
      near: failed  true  end  >>> end  Procedure 
FAIL tset7.pp — compile error:
    pascal26:36: error: invalid optional IR node reference in block first
      near:  test  r   >>> end  unit 
SKIP tstring4.pp — wontfix: reads ansistring refcount/length header words — FPC internal string layout
test-pascal-conformance: 56 pass, 2 fail, 28 skip, 5 auto-gated (of 91)
test-pascal-conformance: FAILURES: tset2.pp(compile) tset7.pp(compile)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-18 — auto-closed by the plexus watcher: `test-pascal-conformance#shard4/6` passes at 5b43ad800d23 (tier full); it was red at 61e2448bac6d. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
