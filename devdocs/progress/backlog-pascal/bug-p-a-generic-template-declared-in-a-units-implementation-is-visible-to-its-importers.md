---
slug: bug-p-a-generic-template-declared-in-a-units-implementation-is-visible-to-its-importers
track: P
prio: 35
type: bug
status: backlog
blocked-by: []
created: 2026-09-04
found-by: frankB
summary: "`Templates[]` is a flat global array with NO unit or section channel -- no TemplateUnitIdx, no TemplateDeclImpl -- so a generic template declared in a unit's IMPLEMENTATION section is nameable by every importer. FPC 3.2.2 refuses it (`Identifier not found`). PRE-EXISTING: the pinned binary accepts it too, so this is not fallout from bug-p-a-units-implementation-section-is-visible-to-its-importers -- it is the one declaration table that change could not reach, because it is not a declaration table. Filed at frankD's request, who closed the boundary for the other eight and has no coverage here."
---

# A generic template declared in a unit's implementation is visible to its importers

## Repro

`pe.pas`:

```pascal
unit pe; {$MODE DELPHI}
interface
function Dummy: Integer;
implementation
type TPriv<T> = record V: T; end;     { declared in the IMPLEMENTATION }
function Dummy: Integer;
var p: TPriv<Integer>;
begin p.V := 5; Result := p.V; end;
end.
```

```pascal
program p4; {$MODE DELPHI}
uses pe;
var q: TPriv<Integer>;                { the importer NAMES the private template }
begin q.V := 9; writeln(q.V, ' ', Dummy); end.
```

| | result |
| --- | --- |
| FPC 3.2.2 | `Error: Identifier not found "TPriv"` |
| pxx at 888564ca11ba | **compiles, runs, prints `9 5`** |
| pxx at the pin `c31d03b202da` | **compiles** — pre-existing |

The unit's OWN use is fine on both and must stay that way (`P5 5` under pxx and
FPC alike).

## Why the boundary work did not cover it

`bug-p-a-units-implementation-section-is-visible-to-its-importers` stamped every
DECLARATION table with the section its rows were declared in — alias, arraytype,
enumtype, uclass, strconst, setconst, sym, proc — and `Specializations[]` gained
the same stamp the same day. `Templates[]` did not, and could not: it is not a
declaration table. It is a token-arena registry, and its only per-row channels
are `TemplateNParams`, `TemplateSrcKey`, `TemplateIsDelphi` and the parameter
names. There is nowhere for a visibility answer to live.

```
$ grep -rn "TemplateUnitIdx\|TemplateDeclImpl" compiler/
(no output)
```

## Is it a defect? Yes, and the argument is the boundary's own

"Us accepting what FPC rejects is not a defect" is the general rule, and on its
own this would be a permissive divergence. It is filed anyway because it is the
**same harm shape the boundary ticket measured**: builtinheap's private
`PWord = ^NativeInt` outranked the builtin `PWord = ^UInt16` in every program
that touched the heap, so `PWord(p)^ := x` wrote eight bytes where the source
said two. A unit's private `TList<T>` leaking into every importer is the generic
analogue — a name the author deliberately kept internal, silently in scope, able
to collide with or outrank a user's own.

It also means **a unit cannot have a private generic type at all**, which is an
encapsulation hole rather than a leniency.

## Where to start, and what to measure FIRST

Add `TemplateUnitIdx[]` + `TemplateDeclImpl[]` beside `TemplateSrcKey[]`,
stamped in `ParseGenericTemplateNamed` from `CurrentUnitIdx` / `DeclInImplNow`,
and make the two by-name lookups — `IsGenericTemplateName` and the arity scan in
`ParseSpecialization` — ask `DeclVisibleSect` with a new `IMPLTAB_TEMPLATE`.

**Measure the corpus before changing behaviour.** `lib/rtl`, rtl-generics and
the fpc testsuite corpus have not been checked for reliance on the leak, and a
template resolved through it today would start failing. `PXXDBG=p.implleak`
reports every row the boundary would hide instead of hiding it, which is the
cheap way to get that census in one run once the tag exists.

Not folded into
[[bug-p-a-specialization-minted-in-a-units-implementation-is-seen-by-the-importers-duplicate-test]]:
that one was a same-day regression on the SEAM between two visibility checks and
is fixed. This one is older than both and is about a table that has no
visibility channel at all.
