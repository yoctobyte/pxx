---
track: P
prio: 35
type: feature
blocked-by: []
summary: "Six TObject members FPC has and pxx rejects at compile time: ClassParent, InstanceSize, ClassInfo, ToString, Equals, GetHashCode. Loud failures (not wrong values), found by the same probe as bug-p-a-class-does-not-inherit-from-tobject-at-run-time."
status: backlog
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
