---
slug: bug-b-rtl-provides-no-ienumerable-generic-interface
track: B
prio: 55
type: bug
status: backlog
owner: unassigned
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
