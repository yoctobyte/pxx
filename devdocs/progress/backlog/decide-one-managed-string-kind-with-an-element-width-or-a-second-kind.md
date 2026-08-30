---
slug: decide-one-managed-string-kind-with-an-element-width-or-a-second-kind
title: "DECIDE: one managed-string kind carrying an element width, or a second kind — 636 sites say it matters"
track: U
prio: 60
type: decide
status: open
created: 2026-08-30
found-by: frank-coordinator
summary: "The UTF-16 model was decided as a distinct tyWideString kind. Measurement after the fact says that costs a 636-site audit with no chokepoint and silent failures, which contradicts the owner's stated 'almost free'. Option B -- one managed-string kind carrying an element width -- costs nothing at those sites. One AST measurement decides whether B is actually cheaper."
---

# The fork

The owner asked, when raising string types on 2026-08-30:

> "all (dynamic) strings can use the same ansistring work… if all is well, **we can just tag
> the type**, and the rest should more or less be library/track B work. so, implementing new
> string types is **(almost) free**, give or take some conversion helpers where needed.
> **or do i overlook a something?**"

**636 is the answer to that question.** It was overlooked, and it was overlooked by the
coordinator too — the resolution that picked a distinct kind was written before anyone
counted.

## What was measured, by frankwasm, at HEAD in `compiler/*.inc`

| | count |
| --- | --- |
| `tyAnsiString` mentions, all | 824 |
| …code-level kind **tests** | **636** |
| …the `(x = tyAnsiString) or (x = tyString)` any-string shape | 97 |
| `TypeIsManagedStr` — the predicate that exists to normalise exactly this | **5 call sites** |
| `tyWideChar`, for contrast (a scalar that DID take its own ordinal) | 19 |

The last two rows are the finding. A chokepoint **exists** — `symtab.inc:3157
TypeIsManagedStr`, whose entire body is `Result := (tk = tyAnsiString)` — and it is
essentially unadopted: five calls against 636 direct tests.

## Option A — `tyWideString` as a distinct kind (as currently decided)

Matches the `tyWideChar` precedent. Explicit at every use. **Costs:** every one of those 636
tests that means *"is this a string"* rather than *"is this specifically an AnsiString"*
needs a third arm, added individually, with no way to find the missed ones except the bug
they cause. **A miss does not fail loudly** — it treats a wide string as not-a-string, which
is a leak or a silent wrong value. This is `normalise-dont-special-case.md`'s exact failure
mode at 636x.

## Option B — ONE managed-string kind carrying an ELEMENT WIDTH (recommended)

`tyAnsiString` stays *the* managed string kind; the element is `tyChar` or `tyWideChar`. All
636 sites keep working untouched, because a wide string genuinely **is** a managed string.
Only width-sensitive sites change: `Length` (>>1), indexing (stride 2), literal encoding,
`Write`, the transcode boundary.

**Three independent supports:**

1. **The runtime half is already built this way.** It needed no second block shape, no second
   refcount path, no second free path — because the difference was never the kind, it was the
   element width, and the header stayed a byte count. Modelling in the type system a
   distinction the runtime does not make is how the two drift.
2. **`TTypeRef` already carries `Kind` + `ElemTk`/`PtrDepth`/`DynDepth`** for precisely the
   "same kind, different shape" case. A wide string is `Kind = tyAnsiString, ElemTk =
   tyWideChar` — an existing field doing its existing job. B adds zero new mechanisms.
3. **FPC's own RTTI collapses the two spellings**: `TypeInfo(WideString)^.Kind` and
   `TypeInfo(UnicodeString)^.Kind` are **both 24 (`tkUString`)** on Linux, measured on
   fpc 3.2.2 rather than recalled.

The five real lockstep sites under A — `FieldIsManaged` (`rtti_emit.inc:24`) and four
finalizer/member-kind sites (:1337/:1367/:1456/:1490) — are each a **leak if missed** under A
and **change not at all** under B. That is the argument in miniature.

## The measurement that decides it — IN FLIGHT

Under B the element width must ride on an **expression** node, not only a symbol, because the
wall is `WideChar(u1) + WideChar(u2)` and that `+` result has no declaration to hang a width
on. `ASTTk` carries one kind per node.

frankwasm is measuring whether a node-level element slot already exists, starting from how
`s1 + s2` on two `tyAnsiString`s already knows its element size is 1. Outcomes:

- **slot exists** → B strictly cheaper, no fork, proceed
- **no slot, adding one is bounded and additive** (as `tyWideString` was) → still B
- **no slot and adding one is invasive** → **genuine fork, this ticket is live**

## State — nothing is half-done

The alias is **not** broken. `tyWideString` is landed additive and readers-free
(`ce693b1d5120`); the runtime half is landed and tested (surrogate pairs, lone surrogates,
truncated leads); `WideString` still resolves to `tyAnsiString`/`tyString` exactly as before.
Under B the ordinal-32 kind is deleted or repurposed at zero cost. Under A work resumes in
place.

## Carried regardless of the outcome

Both resolver sites are guarded by `PasDefineExists('PXX_MANAGED_STRING')`, and **both arms
build today** and both match fpc 3.2.2 for ASCII. Whichever option wins, the acceptance test
must **name the arm it ran under and run both** — a one-arm green lets the change land in one
configuration and silently miss the other. Same shape as
`bug-a-the-cdecl-soundness-reject-still-has-its-argument-shaped-door-on-four-targets`, one
level down: the untested axis is the build configuration instead of the target.

sysutils' `WideString`/`UnicodeString` identity functions are **documented** as the identity;
the moment the alias breaks, that documentation becomes wrong rather than stale. Same commit.

## The measurement that should decide it: **6 findable vs 636 unfindable**

Not "636 versus a 5-call chokepoint" — that names the count, and the count is
not the property that matters. The decision turns on **findability**:

- Option B's cost is **6 per-backend COW guards**, all spelling
  `(IRTk[left] = Ord(tyAnsiString)) and (elemSize = 1)`. One exact grep, one
  shape, found in a single command. A miss is impossible to hide.
- Option A's cost is **636 `tyAnsiString` kind tests** that are NOT mechanically
  separable into "means any string" (needs a third arm) and "means specifically
  AnsiString" (must not get one). Each must be judged individually, and a miss
  is invisible until it produces a wrong value.

**A large mechanically-enumerable set is cheap; a small set that must be judged
one site at a time is not.**

Evidence that A's unfindable misses are real rather than theoretical, found
while measuring and from a direction nobody had counted: under A, `Length` on a
wide string **returns garbage**. Every backend's Length path tests
`IRTk = tyAnsiString`; under A that test fails for a wide string, so Length
falls through to the dyn-array catch-all and reads the wrong word. Not a compile
error, not a leak — a wrong number from the most-called string operation in the
language. That is the third independent instance of A's silent-failure mode, and
it was found by accident, which is the point.

Under B that same test still passes and returns the byte count, so the halving
is a frontend shift and no backend changes at all.
— frankwasm, 2026-08-30
