---
track: U
prio: 42
type: decide
blocked-by: []
status: decided
summary: "TObject.ClassInfo is the last member of feature-pascal-builtin-tobject-class still PXX-REJECT, and it is a judgment call, not an implementation choice: our RTTI blob is honest for identity comparison and wrong for anything that walks FPC's TTypeInfo layout. Answer or refuse — the third option is to answer and be silently wrong for the second caller."
owner: ""
---

# Decide: `TObject.ClassInfo` — answer with our blob, or keep refusing?

Filed 2026-08-25, after `UnitName` landed and left this the only PXX-REJECT
member of [[feature-pascal-builtin-tobject-class]]. The same trade-off is
stated in [[feature-p-tobject-api-classparent-instancesize-tostring]]; it has
now been stated twice and decided zero times, which is why it is a `decide-`.

## The fork

`ClassInfo` in FPC returns a `Pointer` to the class's `TTypeInfo` — a
documented layout (`kind: TTypeKind` byte, `name: ShortString`, then a
kind-specific `TTypeData`) that `typinfo.pp` and every RTTI-walking library
reads field by field. Our class RTTI blob is a different, larger structure
(`name ptr, parent, instSize, vmt, …, unitName`) with a pointer-to-interned-
name at +0, not a kind byte.

Two kinds of caller:

- **Identity only** — `if A.ClassInfo = B.ClassInfo`, `GetTypeData(x.ClassInfo)`
  used purely as a token, storing it in a registry. Our blob serves these
  perfectly: it is unique per class, stable, and non-nil.
- **Layout walkers** — anything that reads `PTypeInfo(x.ClassInfo)^.Name` or
  hands it to `typinfo`'s `GetPropList`. Our blob would be read as a
  `TTypeKind` byte plus a ShortString, off a pointer's low byte. Garbage, and
  garbage that *looks* like an answer.

## Options

1. **Refuse (status quo).** `x.ClassInfo` errors, naming this ticket. Nothing
   silently wrong. Costs: `tclassinfo1.pp` stays skipped, and any real code
   using ClassInfo as a token stops at the first use.
2. **Answer with our blob.** Cheap (one arm in `GenMakeClassRefOp`, one
   accessor). Identity callers work. Layout walkers read garbage with no
   diagnostic — the exact failure mode this repo keeps paying for.
3. **Emit a real FPC-shaped `TTypeInfo` prefix** in front of (or beside) each
   class blob and answer with that. Correct for both caller kinds; costs the
   kind byte + ShortString name per class, and pins us to FPC's layout for
   `tkClass` where today we own our format.

## Recommendation

**(1) now, (3) when a corpus actually needs it.** Refusing is not a gap here so
much as a correct answer to an ambiguous question, and it costs one skipped
conformance test. (2) is the option that trades a loud refusal for a silent
wrong value, which the repo's own rule forbids by default; if it is chosen
anyway it should be behind a flag and say so in the docs.

Note (3) is not much bigger than (2) once a blob word is being added at all —
`UnitName` just showed the header can grow freely, because nothing strides over
these headers and every reader names a field offset.

## What unblocks on the answer

`tclassinfo1.pp` (conformance), and the ClassInfo line of
[[feature-pascal-builtin-tobject-class]] and
[[feature-p-tobject-api-classparent-instancesize-tostring]].

---

# DECIDED 2026-08-25 — **option 3: answer with a real FPC-shaped `TTypeInfo`**

Decided by an agent under the no-human-available rule
(`devdocs/progress/decided/README-agent-decisions.md`). **Derived.**

`x.ClassInfo` returns the typinfo facade's `PTypeInfo` header — the same value
`TypeInfo(TThatClass)` already mints today (`{Kind; NamePtr; DataPtr}`, with
`DataPtr` pointing at our class blob). Both caller kinds are then served:
identity holds (`o.ClassInfo = TypeInfo(TFoo)`, which is what `tclassinfo1.pp`
asserts), and a layout walker reads a real kind byte and a real name.

**Option 2 is forbidden by a stated rule**, not merely disfavoured —
`frontend-compat-philosophy.md`: *"a silent wrong VALUE is a bug in any
dialect."* Option 1 (refuse) is the right answer only while no correct answer
exists; one does, and the ticket's own note says why it is cheap: *"(3) is not
much bigger than (2) once a blob word is being added at all — `UnitName` just
showed the header can grow freely."*

This ticket and [[decide-classinfo-returns-our-blob-or-nothing]] are the same
question asked twice with different option letters, which is itself why it went
undecided: each looked like it might be the other's duplicate. **The full
derivation, including the per-class-vs-on-demand sub-question (answer: per
declared class, one word each), is recorded in that ticket.** Work is re-filed
there as `feature-a-classinfo-returns-the-typinfo-header` (Track A, prio 45).

## Log
- 2026-08-25 — decided, commit PENDING-COMMIT.
