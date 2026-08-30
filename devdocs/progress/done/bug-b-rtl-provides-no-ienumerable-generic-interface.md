---
slug: bug-b-rtl-provides-no-ienumerable-generic-interface
track: B
prio: 55
type: bug
status: done
owner: frankB
blocked-by: []
summary: "FPC's implicit ObjPas unit declares `generic IEnumerator<T>` / `generic IEnumerable<T>` (rtl/objpas/objpas.pp:79-88) and the non-generic `IEnumerator` / `IEnumerable` (rtl/inc/objpash.inc:272-283). Our RTL declares none of the four — `grep -rn IEnumerable lib/rtl/*.pas` is empty. rtl-generics' `TList<T>.AddRange(const AEnumerable: IEnumerable<T>)` therefore fails with `unknown type: IEnumerable`, which is the CURRENT rtl-generics corpus wall (rung 6b) as of aa572136dc9c. Not a compiler bug: a control declaring a generic interface locally and using it as a parameter type of a generic class compiles and runs."
---

# `IEnumerable<T>` / `IEnumerator<T>` are missing from the RTL

## Measured

Corpus `packages/rtl-generics/src`, probe `program gcprobe; uses
Generics.Collections; begin end.`, no `-dVER3_0_0`, binary `aa572136dc9c`
(self-host fixedpoint at HEAD). The whole output is two errors:

```
pascal26:259: error: unknown type: IEnumerable
pascal26:259: error: expected ')' before '>'
```

`generics.collections.pas:259` is

```pascal
    procedure AddRange(const AEnumerable: IEnumerable<T>); overload;
```

**The `near:` text on that error points somewhere else entirely** — it is stale
after a token splice, which is
[[bug-a-the-near-context-window-is-stale-after-a-token-splice]]. Reduce from the
FILE and LINE, never from `near:` on this corpus.

## Why it is a library gap and not a compiler gap

`IEnumerable` is declared in neither the corpus nor our RTL:

```
$ grep -rn IEnumerable <corpus>/generics.defaults.pas <corpus>/inc/*.inc   # only USES
$ grep -rn IEnumerable lib/rtl/*.pas                                       # nothing
```

FPC supplies all four from the implicitly-used ObjPas/System units:

| declaration | FPC source |
| --- | --- |
| `generic IEnumerator<T>` | `rtl/objpas/objpas.pp:79` |
| `generic IEnumerable<T>` | `rtl/objpas/objpas.pp:86` |
| `IEnumerator` (TObject-based) | `rtl/inc/objpash.inc:273` |
| `IEnumerable` | `rtl/inc/objpash.inc:280` |

**Control — the compiler handles the shape.** A generic interface declared
locally and used as a parameter type of a generic class, alongside an overload
on the bare parameter, compiles and runs (`tiface.pas`, mode delphi, prints
`val 5`). So nothing here is waiting on Track P or Track A; the four
declarations are simply absent.

## The shape to add

```pascal
  IEnumerator<T> = interface
    function GetCurrent: T;
    function MoveNext: Boolean;
    procedure Reset;
    property Current: T read GetCurrent;
  end;

  IEnumerable<T> = interface
    function GetEnumerator: IEnumerator<T>;
  end;
```

plus the two non-generic `TObject`-based ones. Where they go is the open
question and is worth deciding before writing them: FPC puts them in the
implicit ObjPas unit so that no `uses` is needed, and rtl-generics relies on
exactly that. Putting them anywhere a program must `uses` would not fix the
corpus.

**`property ... read` on an interface** is the one shape in the block above that
should be checked against pxx before assuming it compiles; if it does not, that
is a Track P ticket and this one becomes `blocked-by` it.

## Provenance

Found by [[bug-p-the-rtl-generics-corpus-stops-on-tkey-in-a-tlist-body]] moving:
that ticket's `unknown type: TKey` wall is fixed (template capture overrun on a
bodiless nested class) and this is what the corpus reaches next. Corpus read
from `/home/neo/pxx/library_candidates/rtl-generics/packages/rtl-generics/src`.
Run time ~1m30s.

---

## RESOLVED 2026-08-30 (frankB) — and the ticket's premise about placement was wrong

`IEnumerator<T>` / `IEnumerable<T>` are declared in **`lib/rtl/classes.pas`**.
Corpus re-run: the two `unknown type: IEnumerable` errors are gone.

### The premise that was wrong, because it is the reusable part

This ticket said:

> Putting them anywhere a program must `uses` would not fix the corpus.

**That is false for this corpus, and checking it took one grep.**
`generics.collections.pas:43` reads

```pascal
uses
    RtlConsts, Classes, SysUtils, Generics.MemoryExpanders, Generics.Defaults,
    Generics.Helpers, Generics.Strings;
```

— and `RtlConsts`, `Classes` and `SysUtils` are all **ours** (`lib/rtl/`). So
`Classes` is a place the caller already reaches, and no implicit-unit machinery
was needed at all. The reasoning that produced the wrong premise was sound about
FPC (it really does use the implicit ObjPas unit *so that* no `uses` is needed)
and simply never asked what this particular caller already imports. **"FPC needs
mechanism X for reason R" does not imply we need X, when our caller's own `uses`
clause already solves R.**

The genuine limitation, stated rather than hidden: a program using these
**without** `uses Classes` still fails where FPC would succeed. Recorded in the
source comment, not just here.

### What shipped, and what deliberately did not

- Both generic interfaces, **without** FPC's `property Current: T read GetCurrent;`
  — pxx rejects a property inside an interface outright. Filed as
  [[bug-p-a-property-in-an-interface-declaration-is-rejected]] with the control
  that matters: an **uninstantiated** generic interface carrying a property
  compiles clean because its body is never parsed, so the obvious check returns a
  **false green**. That was this ticket's own flagged unknown, and it was right to
  flag it.
- **Not** the non-generic `TObject`-based pair from `objpash.inc:273/280`:
  nothing in the corpus references it. `IEnumerator` is in fact referenced **zero**
  times by the corpus; only `IEnumerable<T>`, six times, all `AddRange` parameters.

### Where rung 6b now stands

One error, not two, and it is a compiler limit rather than a library gap:

```
pascal26:127: error: too many generic parameters (MAX_TEMPLATE_PARAMS)
  in: .../inc/generics.dictionariesh.inc
```

`TDictionaryEnumerable` declares **six** type parameters (three of them via the
`CUSTOM_DICTIONARY_CONSTRAINTS := TKey, TValue, THashFactory` macro) against
`MAX_TEMPLATE_PARAMS = 4`. Filed as
[[bug-a-max-template-params-is-4-but-rtl-generics-declares-6]] — Track A, since
it is `compiler/defs.inc`.

### Gate

`make lib-test` **green** against stable v398, `classes` job included; plus a
`TStringList` smoke (Create/Add/Sort/index/Count) to confirm the additive change
did not disturb the existing surface. Compile time for the corpus probe rose
75s -> 118s, which is consistent with getting further rather than with a hang.

## Log
- 2026-08-30 — resolved, commit 6e1515c4a.
