---
track: P
prio: 62
type: bug
blocked-by: []
summary: "A method declared in a descendant WITHOUT `overload` must HIDE every inherited method of that name. pxx keeps the inherited ones as candidates, so a call can silently dispatch to the parent's differently-typed method — `l.Add(TFoo.Create(3))` on fgl's TFPGList<IFoo> reaches TFPSList.Add(Pointer), stores the object's VMT word, and the next read segfaults."
status: backlog
owner: —
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
