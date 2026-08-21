---
prio: 70
status: done
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-pascal-conformance#shard4/6 red at 1b9b43e5b511 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-20T16:41:34Z
- **Test source:** tools/run_pascal_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-pascal-conformance#shard4/6'` at 1b9b43e5b511d53e9fbe55f3366e6ce9158ee0b9

## Range
bad `1b9b43e5b511`, last good `57b9b7148d32`, 132 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL tgeneric96.pp — compile error:
pascal26:16: error: unknown type: TLongIntTest
(tail)
KIP tgeneric106.pp — gap: generic class with `class var` procvar field of type G<T>, method-of-object
SKIP tgeneric14.pp — wontfix: dialect-pass — test header says %fail is an FPC IMPLEMENTATION limitation ("assembler symbols not global"), not a language rule — PXX passing is correct
SKIP tgeneric1.pp — gap: objfpc `generic TList<_T> = class` / `specialize` syntax not parsed
SKIP tgeneric30.pp — wontfix: dialect-pass — mode-delphi generic method impl without <T> — PXX's Delphi-generics rewriter deliberately accepts the bare name (3d71edcf); not a bug
SKIP tgeneric63.pp — gap: generic record with nested record type
SKIP tgeneric7.pp — gap: generics across units + $R range-check state per unit (expects runtime error 201)
SKIP tgeneric85.pp — gap: accepts-invalid — invalid generic record body accepted (pre-specialization checking)
FAIL tgeneric96.pp — compile error:
    pascal26:16: error: unknown type: TLongIntTest
      near: LongInt   var lt  >>> TLongIntTest  t 
SKIP tgenfunc3.pp — gap: generic class functions (generic class function Add<T>) not supported
SKIP tgenfunc9.pp — gap: generic methods with private/protected visibility specialized from caller
SKIP tmoperator11.pp — gap: management operator class operator Initialize on records
SKIP tobject2.pp — gap: old-style `object` types with virtual methods, constructor/destructor
SKIP toperator1.pp — gap: operator overloading (+) on records declared in units; cross-unit operator resolution
SKIP toperator9.pp — gap: operator overload for `in` on a record type not supported by the parser
SKIP tprocvar1.pp — gap: method pointers (`procedure(l:longint) of object`), @Class.Method, typed-const procvars
SKIP tsealed6.pp — gap: `object abstract` / `object sealed` modifiers in object declarations
SKIP tstring4.pp — wontfix: reads ansistring refcount/length header words — FPC internal string layout
test-pascal-conformance: 57 pass, 1 fail, 28 skip, 5 auto-gated (of 91)
test-pascal-conformance: FAILURES: tgeneric96.pp(compile)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Root cause found and fixed — 2026-08-21 (agent-A)

Real and reproducible, but **not a regression** — `tgeneric96.pp` fails
identically on the PINNED binary and on `57b9b7148d32`'s tree, and it is not in
`pxx.skip` at either end of the range. The shard flipped because shard
membership is `index mod 6` over the corpus listing, so a test moving between
shards reads as "shard 4 changed behaviour at a commit that touched no code" —
the shape `bug-t-regressions-are-blamed-on-commits-that-touch-no-code` already
describes.

**The bug: `Specializations[]` is one flat global table, but a specialization
is not a global fact.** `SpecializeStream` declares an ordinary class under the
alias name in whatever unit is being parsed, and that declaration obeys the
same one-hop `uses` rule as every other type — `FindUClass` already filters on
`DeclVisible`. `FindSpecialization` did not. So when two units each write

```pascal
type TLongIntTest = specialize TTest<LongInt>;
```

without using each other, the second one hit ParseSpecialization's
"already declared, this is an exact re-statement, no-op" shortcut, skipped its
own declaration, and the very next line — `var lt: TLongIntTest;` — failed with
`unknown type: TLongIntTest` **in a unit whose own source declares it**.

Minimal repro (no generic/non-generic homonym needed, so the arity half of
tgeneric96 was never the problem):

```
ugd.pp:  generic TTest<T> = class end;
uga.pp:  uses ugd;  type TLongIntTest = specialize TTest<LongInt>;  var lt: TLongIntTest;
ugb.pp:  uses ugd;  type TLongIntTest = specialize TTest<LongInt>;  var lt2: TLongIntTest;
p.pp:    uses uga, ugb;
```

Each unit compiles alone. Together: `ugb.pp:8: unknown type: TLongIntTest`.
Different alias name → fine. Same alias, different arguments → fine. It takes
same name AND same arguments, which is exactly what makes the shortcut fire.

**Fix:** `FindSpecialization` is visibility-aware — it skips rows whose
`SpecUnitIdx` this scope cannot see, and among the visible ones the last wins,
matching `FindUClass`'s "later unit hides the earlier" rule. A unit that cannot
see the earlier specialization now materialises its own, which the class table
has supported all along (the duplicate-class diagnosis is explicitly scoped to
the declaring unit). The rtl-generics case the shortcut was written for —
two deferrals emitting the same prerequisite inside ONE unit — still takes it,
because `DeclVisible(CurrentUnitIdx)` is trivially true.

The sibling `NestedSpecKnown` is fixed by the same change: it asks
`FindSpecialization` too, so a nested prerequisite in an unreachable unit no
longer reads as satisfied.

**Verified:** shard 4/6 is **58 pass, 0 fail**; the whole `tgeneric*` category
is 55 pass, 0 fail. Regression guard `test/test_generic_spec_per_unit.pas` +
`test/generic_spec_units/` reproduces tgeneric96 in full — both uses orders of
a generic `TTest<>` and a non-generic `TTest`, one specialization per unit —
prints `total ok 4 / 4` under pxx and under FPC 3.2.2, and fails to compile on
the pinned pre-fix binary.

Gate: `make compiler/pascal26` + `tools/gate.sh quick` GREEN.
- 2026-08-21 — resolved, commit d30d3e1fc.
