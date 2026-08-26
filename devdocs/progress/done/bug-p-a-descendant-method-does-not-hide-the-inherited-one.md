---
track: P
prio: 62
type: bug
blocked-by: []
summary: "A method declared in a descendant WITHOUT `overload` must HIDE every inherited method of that name. pxx keeps the inherited ones as candidates, so a call can silently dispatch to the parent's differently-typed method — `l.Add(TFoo.Create(3))` on fgl's TFPGList<IFoo> reaches TFPSList.Add(Pointer), stores the object's VMT word, and the next read segfaults."
status: done
owner: opus5-frank1
---

# A descendant method does not hide the inherited one

Found 2026-08-26 by narrowing the last failing fgl driver. It was filed the same
day as *"an interface retrieved from a generic container segfaults"*; that title
described the symptom and this one describes the cause, which measurement turned
out to be neither interface-specific nor generic-specific.

## The language rule pxx does not implement

In Object Pascal a method declared in a descendant **hides** all inherited
methods of the same name, unless it is marked `overload` (or `override`, which
continues the same method). pxx keeps the inherited ones as overload candidates
regardless. The directive parser says so outright, and states the assumption
that makes it look safe:

> inline/**overload**/static/reintroduce + hint directives are parse-and-ignore:
> **overload resolution is signature-keyed anyway** ...

That assumption holds exactly while no two candidate signatures both accept the
argument. When they do, the call silently goes to the wrong one.

## Measured (pxx `c6a3ea453`; oracle fpc 3.2.2)

```pascal
type
  TBase = class
    function Add(x: Pointer): Integer;          { no overload directive }
  end;
  TDer = class(TBase)
    function Add(const s: AnsiString): Integer; { no overload directive -> HIDES }
  end;
...
  d.Add('hello');
  d.Add(p);        { p: Pointer }
```

| | fpc 3.2.2 | pxx |
| --- | --- | --- |
| `d.Add('hello')` | `DER hello` | `DER hello` |
| `d.Add(p)` | **`Error: Incompatible type for arg no. 1: Got "Pointer", expected "AnsiString"`** | **`BASE`** — silently dispatches to the hidden parent |

No interfaces, no generics, no fgl. Nine lines.

## How it reaches a segfault

`rtl/objpas/fgl.pp` declares, with no `overload` on either:

```pascal
TFPSList = class ... function Add(Item: Pointer): Integer;         { line 75 }
TFPGList = class(TFPSList) ... function Add(const Item: T): Integer; { line 147 }
```

So `l.Add(TFoo.Create(3))` on `specialize TFPGList<IFoo>` must call
`TFPGList.Add`, which converts the class instance to `IFoo` and passes `@Item`.
pxx instead binds `TFPSList.Add(Item: Pointer)` — a class instance is compatible
with `Pointer` — which does `Move(Item^, ...)`, i.e. it DEREFERENCES the
argument. So the eight bytes stored are the object's first word, its VMT
pointer.

Instrumented (a copy of fgl.pp with WriteLns in `TFPGList.Add`/`Get`), the proof
is that `TFPGList.Add` is never entered at all while `Count` still becomes 1:

```
count 1
DBG Get enter 0
DBG Get ptr=128965305960280 word=4522534      <- 0x45_01E6, inside the image: a VMT, not a heap object
Segmentation fault
```

`Get` then evaluates `T(p^)` on that word, the interface assignment calls
`PXXIntfIMTOf` on it (confirmed by symbolicating the crash address against the
.map), and it dies.

The integer, string and object instantiations pass because no `Pointer` overload
competes for their argument type — which is why six of the seven fgl drivers are
green and this looked interface-specific.

## What it is NOT

Ruled out by measurement, each with a standalone repro that matches fpc exactly:

- the interface cast of a raw deref (`g := IFoo(p^)`) — correct;
- that cast assigned to a function `Result` — correct;
- the same through an `inherited` call result (`IFoo(inherited Get(i)^)`) — correct;
- `@Item` on a `const` interface parameter — correct, and it is the slot;
- fgl's `CopyItem` body written out by hand — matches fpc line for line;
- a hand-rolled `generic TBox<T>` over `array of T` with `T = IFoo` — correct.

So the interface primitives, the cast, the generic machinery and the address-of
are all fine. It is the DISPATCH.

## The fix, and why it is not a small one

Three parts:

1. Record the directive: a `UMthIsOverload` parallel to `UMthProc_`, set where
   `tkOverload` is currently parsed and dropped in `pasparser_decl.inc`
   (the class-body site ~4783 and the record-method site).
2. In candidate COLLECTION, stop climbing `UClsParent` once a level has declared
   the name and none of that level's declarations is `overload`. The ranking
   itself does not change.
3. Do the same in every other lookup that walks the chain — `FindUMeth`,
   `FindUMethArity`, and the several walks in `symtab.inc` — or the ranked path
   and the by-name paths will disagree about which method exists, which is the
   two-mechanisms failure this codebase keeps paying for.

Part 3 is why this is prio 62 and not a quick fix: it changes NAME RESOLUTION
globally, so the blast radius includes the self-host, every corpus rung and any
pxx-accepted source that currently relies on an inherited overload staying
visible. It needs its own change with its own measurement of what it breaks, not
a ride-along.

A narrower version — hiding applied only in `FindUMethOverloadArgs`, the one
ranked path where this bug happens — would fix fgl and leave the by-name lookups
disagreeing with it. That is the microfix this ticket exists to avoid.

## Repro / gate

The nine-line `TBase`/`TDer` case above rejecting `d.Add(p)` as fpc does, plus
`test/fgl/ifclist.pas` — skip-listed against this ticket in `test/fgl/pxx.skip`.
Remove the line when fixed; `tools/run_fgl_corpus.sh` then takes the rung
6/7 -> 7/7.

Gate = `make compiler/pascal26` (self-host fixedpoint) + `tools/gate.sh quick`.

## Links
Rung: [[feature-pascal-corpus-fgl]] · umbrella
[[feature-pascal-corpus-expansion]] ·
found behind [[bug-p-a-cast-as-lvalue-does-not-accept-a-builtin-type-name]]

# Outcome — 2026-08-26

Implemented, and the fgl rung is now **7 pass / 0 fail / 0 skip** —
`test/fgl/pxx.skip` has no entries left.

## The three parts, as filed

1. **Record the directive.** `UMthHidesInherited` beside `UMthIsStatic`, set at
   the Pascal CLASS-BODY declaration site to
   `(not overload) and (not override) and (not constructor)`.

   `override` had to clear it: an override CONTINUES the inherited method
   rather than introducing a new one, so hiding there would have made
   `b.G(1)` — an inherited `overload` sibling — disappear. Constructors had to
   be excluded too: FPC treats them as always overloaded across a hierarchy, so
   hiding them would break every class that adds a `Create`. Both are measured
   rows in the test, not guesses.

   The flag stays False for the other frontends (NilPy, C, Rust, Zig register
   their methods through the same `AddUMeth` but have no such rule), for
   INTERFACE methods (an interface's parent chain is its IMT layout, not a
   hiding relation) and for RECORD methods (pxx's records do not inherit). That
   is `the-substrate-is-ast-and-ir-not-the-parser.md`'s "normalise within a
   language, duplicate across languages" — and it is why the change costs NilPy
   nothing.

2. **Stop the ranked walk.** `FindUMethOverloadAhead`'s candidate collection
   breaks out of the parent chain after a level that hides the name.

3. **Stop the by-name walks too**, which is the part the ticket said was the
   real work. It turned out to be one line in one more place:

   * `FindUMeth` already implements hiding for free — it returns the FIRST name
     match walking outward, so it never sees a shadowed parent method.
   * `FindUMethArity` needed the break, and needed it EVEN WHEN THE ARITY DID
     NOT FIT: falling through to a parent's same-name method of another arity
     is exactly the wrong answer rather than a helpful fallback.
   * `FindUMethForSig` (the IMT builder) and `FindUMethByProc` are keyed by
     signature and by proc index, not by name, so hiding does not apply.
   * The remaining `UClsParent` walks in `symtab.inc` are property lookups and
     virtual-slot lookups — neither is a method-name resolution.

   Both name walks call ONE shared predicate, `UClsLevelHidesMeth`, rather than
   inlining the rule twice. Two copies of a rule is how the ranked path and the
   by-name paths start disagreeing, which is the failure this ticket exists to
   avoid.

The microfix the ticket warned against — hiding only in the ranked path — was
not taken.

## Verification

The nine-line repro no longer dispatches to the hidden parent. Seven shapes
measured against fpc 3.2.2 -Mobjfpc -O1, **all identical**, and they are chosen
so that half of them are cases where hiding must NOT happen:

| shape | fpc | pxx |
| --- | --- | --- |
| virtual call through a base reference | TB.F | TB.F |
| `override` direct | TB.F | TB.F |
| `overload` keeps the inherited one visible | TA.G int | TA.G int |
| `overload` own | TB.G str | TB.G str |
| a constructor does not hide | TA.H int | TA.H int |
| hidden name binds the descendant's | TB.H str | TB.H str |
| hiding through TWO levels | TC.H dbl | TC.H dbl |

Blast radius, measured rather than argued:

* **self-host** converged after 1 round, byte-identical — compiler.pas is
  itself a large class hierarchy.
* `tools/gate.sh quick` GREEN.
* `tools/run_pascal_conformance.sh`: 346 pass, **0 fail**, 170 skip, 34
  auto-gated (of 550) — and the pass/fail SETS diff clean against the sweep
  taken before the change, not just the totals.
* `tools/run_fgl_corpus.sh` against real FPC 3.2.2 `fgl.pp`: **7/7**, up from
  6/7. `ifclist.pas` un-skipped and now enforced.
* Every one of the 1344 `test/*.pas` files compiled and the failures
  categorised: 169, all of them pre-existing — unit-not-a-program, missing
  demo units, and the `*_fail.pas` negative tests. No new resolution failure.

## The residual, deliberately not fixed here

The ticket's gate line asked for `d.Add(p)` to be REFUSED as fpc refuses it.
It is no longer mis-dispatched — it binds `TDer.Add`, the visible method — but
pxx then coerces the `Pointer` to `AnsiString` instead of erroring.

That is not this defect. CLAUDE.md's parity ceiling is explicit: *accepting a
form FPC rejects is not a defect*. And the cause is general, not about hiding
at all — `FindUMethOverloadAhead` type-ranks only when there are 2+ candidates,
so a SINGLE-candidate method call checks arity and nothing else, while the
identical free procedure is refused:

```
FreeProc(p)  -> error: no overload of FreeProc matches these arguments
c.M(p)       -> compiles
```

Filed as
[[bug-p-a-single-candidate-method-call-does-not-check-its-argument-types]].
The hiding fix is what made it visible: it narrowed `d.Add(p)` from two
candidates (a real wrong answer) to one (a looseness).

## Files

* `compiler/defs.inc` — `UMthHidesInherited`.
* `compiler/symtab.inc` — initialised and relocated in `AddUMeth`; new
  `UClsLevelHidesMeth`; `FindUMethArity` breaks the chain.
* `compiler/pasparser_decl.inc` — `isOverloadDir` observed; the flag set at the
  class-body site.
* `compiler/pasparser_call.inc` — `FindUMethOverloadAhead` breaks the chain.
* `test/test_descendant_method_hides_inherited.pas` — new, 8 rows.
* `test/fgl/pxx.skip` — `ifclist.pas` removed; header records 7/7.
* `Makefile` — the new test wired into `test-core`.

## Log
- 2026-08-26 — resolved, commit ddf917c3a.
