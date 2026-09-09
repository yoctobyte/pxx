---
track: P
prio: 15
type: feature
blocked-by: []
summary: "CLOSED 2026-09-09. Was six TObject members pxx rejected; all six now land. ClassInfo was the last and needed a Track U decision, not an implementation: it answers the typinfo facade's PTypeInfo header (the same value TypeInfo(TThatClass) mints), so identity callers and layout walkers are both served -- see feature-a-classinfo-returns-the-typinfo-header. UnitName, never one of the six, is done too."
status: done
---

# TObject API: ClassParent, InstanceSize, ClassInfo, ToString, Equals, GetHashCode

Found 2026-08-20 by the FPC differential probe over the TObject API — the one
that turned up the run-time inheritance bug (now fixed, see
`done/bug-p-a-class-does-not-inherit-from-tobject-at-run-time.md`). These six
are the *loud* half of that probe's findings: each is a compile-time rejection,
so no program silently computes a wrong answer. That is why they are prio 35
rather than a bug.

| member | FPC | pxx |
| --- | --- | --- |
| `TDer.ClassParent` / `o.ClassParent` | the parent `TClass` | PXX-REJECT |
| `o.InstanceSize` | instance byte size | PXX-REJECT |
| `o.ClassInfo` | `Pointer` to RTTI | PXX-REJECT |
| `o.ToString` | `ClassName` by default | PXX-REJECT |
| `a.Equals(b)` | reference equality by default | PXX-REJECT |
| `o.GetHashCode` | an integer derived from the reference | PXX-REJECT |

## Why they are cheap now

The RTTI blob already carries what four of them need, and the parent word is
now correct for **every** class including the implicit-root case, which is what
`ClassParent` reads. `PXX_RTTI_PARENT = 8` gives `ClassParent`; the blob's name
word already backs `ClassName`, so `ToString` is one forwarding method;
`Equals`/`GetHashCode` are pointer identity and need no RTTI at all.
`InstanceSize` needs the size recorded in the blob (check whether it already
is). `ClassInfo` is the blob pointer itself — but note that anything that then
*walks* what FPC's `ClassInfo` returns expects FPC's `TTypeInfo` layout, which
pxx does not emit; returning the pxx blob is honest for identity comparisons
and wrong for structural reflection. Decide that before implementing
`ClassInfo` — the other five have no such ambiguity and can land first.

## Suggested split

Land `ClassParent`, `ToString`, `Equals`, `GetHashCode` together (all trivial,
all fully specified). Then `InstanceSize`. Leave `ClassInfo` for last, or file
a Track U `decide-` if the reflection-layout question needs the owner.

## 2026-08-22 — five of the six landed; only ClassInfo is left

Re-measured against a self-hosted binary at `0332839bc`, on a
`TD = class(TObject)` instance with one Integer field:

| member | 2026-08-20 | today |
| --- | --- | --- |
| `ClassParent` | PXX-REJECT | works |
| `InstanceSize` | PXX-REJECT | works (12) |
| `ToString` | PXX-REJECT | works (`'TD'`), and a descendant's `override` dispatches |
| `Equals` | PXX-REJECT | works, VIRTUAL through a static `TObject` receiver |
| `GetHashCode` | PXX-REJECT | works, same |
| `ClassInfo` | PXX-REJECT | PXX-REJECT |

`Equals` / `GetHashCode` / `ToString` came with
[[feature-a-tobject-root-method-vmt-slots]] (option C of
[[decide-tobject-root-methods-dispatch-model]]) rather than with this ticket, and
they are virtual, not intercepted — which is the property that made them worth
the reserved slots.

**`ClassInfo` is the whole remainder, and this ticket already named why it is not
an implementation choice** ("Decide that before implementing"). Now filed as
[[decide-classinfo-returns-our-blob-or-nothing]]. Dropped to `prio: 20`: what is
left here is one member gated on a decision, not five members of work.

`UnitName` — never in this ticket's six — is the other TObject member still
rejected; it is tracked in [[feature-pascal-builtin-tobject-class]] because it
needs a word added to the class RTTI blob rather than a new accessor.

## 2026-09-09 — `ClassInfo` LANDED. All six members are done; this ticket is closed.

The last row of the table above, and the only one that needed a decision rather
than an implementation. `x.ClassInfo` answers the typinfo facade's `PTypeInfo`
header — the same value `TypeInfo(TThatClass)` mints — so the identity callers
and the layout walkers are both served, and the "answer with our blob" option
that would have served only the first was refused as a silent wrong value.

Work, tests and controls: [[feature-a-classinfo-returns-the-typinfo-header]].
`tclassinfo1.pp` is unskipped and passing.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 5d29682a2.
