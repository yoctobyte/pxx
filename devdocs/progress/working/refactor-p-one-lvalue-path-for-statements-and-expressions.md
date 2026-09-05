---
slug: refactor-p-one-lvalue-path-for-statements-and-expressions
title: "Two lvalue parsers, and the statement one keeps missing what the expression one learned"
track: P
prio: 55
type: refactor
blocked-by: []
status: working
owner: frankA
created: 2026-08-24
summary: "An assignment TARGET is parsed by a second, smaller copy of the lvalue walk in pasparser_stmt.inc, which resolves every `.name` as a field and ends on Expect(':='). Every capability the expression path gains has to be re-added there by hand, and three bugs so far are exactly that omission: the builtin pointer-name fallback, the PChar adapter, and the deref-then-index shape. The statement path should delegate, as its own cast-headed-CALL arm already does."
---

# The shape

`ParseStatementAST` handles `<name>(...)^.f := v` itself: it builds the
AN_PTR_CAST, walks `^` and `.field` in a small loop, then `Expect(tkAssign)`.
`ParseLValueAST` / the expression parser handle the same syntax with far more in
them — default properties, class casts, metaclasses, the `-2` PChar adapter,
depth-carrying derefs, index-over-deref, builtin pointer names.

The statement copy has to be taught each of those separately, and the failure
mode is always the same: the expression spelling works, the assignment-target
spelling is a compile error or a wrong node.

Known instances, all measured:

- `PInteger(p)^ := 42` was "undefined variable" while `WriteLn(PInteger(p)^)`
  compiled — [[bug-p-a-builtin-pointer-cast-is-refused-as-an-assignment-target]]
  (fixed by copying two lines).
- `PChar(p)^ := 'x'` needed the `-2` adapter copied over as well (same ticket).
- The deref chain's own arms (AN_FIELD / AN_INDEX / AN_CALL depth reads) live
  only in `pasparser_lval.inc`, so any target-position use of those shapes is a
  separate question nobody has swept.

# What to do

The statement path already knows how to hand off: its cast-headed-CALL arm says
*"hand the whole thing to the expression parser, which already builds this chain
correctly"*. Do that for the ASSIGNMENT case too — parse the target with the
expression lvalue parser, then `Expect(':=')` and build AN_ASSIGN over whatever
came back — and delete the duplicated walk.

The catch to measure first: the expression parser resolves a trailing `.name` as
a field/method/property and may CALL it, which in target position must not
happen; and it consumes `[` as an index or a default property. Both are decided
before `:=` is seen, so the hand-off needs the same "this is an assignment
target" flag the class-cast arm passes today. Sweep with a differential over
every target shape (bare, field, index, deref, cast, property, default
property) before and after.

# Gate

Track P's, plus a target-shape differential against fpc 3.2.2, plus the
self-host fixedpoint (this path parses every assignment in `compiler.pas`).


---

## 2026-09-02 (frankH) — the differential this ticket asks for now EXISTS, and it is 23/25

This ticket's gate says: *"Sweep with a differential over every target shape
(bare, field, index, deref, cast, property, default property) before and
after."* That sweep has now been built and run against fpc 3.2.2, so the
before-picture is a measurement rather than an expectation.

**25 target shapes. 23 match FPC exactly.** Bare, field, index, deref,
deref-field, deref-index, pointer-cast-deref, pointer-cast-deref-index, class
field, class-field-index, class-field-record-field, class-field-deref, string
index, PChar deref, PChar index, property, named indexed property, default
property, class-cast-field, class-cast-property, with-block field, record-alias
cast field, and non-pointer alias whole assignment.

That number is the useful part, and it changes what this ticket is worth. The
body above lists three instances and says the statement copy "has to be taught
each capability separately" — all three named ones are already fixed, and the
sweep says the remaining divergence surface is **two shapes**, not a class:

1. [[bug-p-a-cast-to-a-string-alias-silently-drops-a-following-index]] —
   `TAlias(s)[2] := 'X'` stores nothing, silently.
2. [[bug-p-a-class-cast-cannot-index-a-default-property-as-an-assignment-target]]
   — `TDerived(b)[3] := v` is refused; FPC stores it. Filed 2026-09-02, and the
   sixth measured instance.

**A third was found by the sweep and FIXED rather than filed**, because it was
the dangerous kind: `type TS = AnsiString; TS(s) := 'z'` stored a managed string
through a POINTER-shaped target — this arm is entered on `FindTypeAlias`, which
finds every named alias, and then stamped `AN_PTR_CAST` / `tyPointer`
unconditionally. Length came back `1073741824` and reading the target walked off
into the heap, with **no diagnostic**. The builtin spelling of the same line,
`AnsiString(s) := 'z'`, was already correct on the pinned compiler — the same
one-concept-two-lookup-paths defect the arms above it each carry a comment
about, arriving by a fourth spelling. Regression test:
`test/test_alias_cast_assign_target.pas`.

### What this means for whoever takes the refactor

- **The harness is the deliverable to reuse.** Its worth is that 23/25 is
  now known, so a unification has a gate instead of a hope. It lives in the
  ticket history rather than in `test/` because it is a before/after
  instrument, not a permanent row; rebuild it from the shape list above.
- **The int and char alias rows are load-bearing.** `TI(i) := 5` and
  `TC(c) := 'q'` go through the very arm that corrupted the string case and
  were already correct, which is why the fix above is scoped to managed strings.
  A refactor that re-routes every non-pointer alias must keep those green — and
  when that was tried here it also turned the silent-index bug into a new parse
  error, i.e. traded a wrong value for a different wrong answer.
- **Two of the remaining shapes refuse loudly and one is silent.** If the
  refactor is ranked on risk removed rather than tickets closed, the silent one
  is the whole argument.

---

## 2026-09-02 (frankH, later) — the surface is now ONE shape, and the silent one is gone

[[bug-p-a-cast-to-a-string-alias-silently-drops-a-following-index]] is fixed
(`9339d6661`), so the divergence list from this morning's sweep reads:

| | |
| --- | --- |
| string-alias cast, indexed, read AND written | **fixed** — all four string flavours, matching fpc 3.2.2 |
| [[bug-p-a-class-cast-cannot-index-a-default-property-as-an-assignment-target]] | still open, and it **refuses loudly** |

**This ticket's argument has changed and whoever ranks it should know how.** The
2026-09-01 sweep noted that *"if the refactor is ranked on risk removed rather
than tickets closed, the silent one is the whole argument."* That silent one is
now fixed, so the remaining case announces itself with a diagnostic. The ticket
is not stale — two lvalue parsers is still the design flaw — but the risk half
of its case is spent, and what is left is tidiness plus one loud refusal.

**And the fix was not a microfix**, which is the part that bears on the refactor
itself: it DELETED a special case. The arm returned early with the subscript
still in the token stream; it now falls through to the suffix loop already
standing below it, and the statement side hands the string to
`ParseClassRecordSelectors` rather than walking it. That is this ticket's own
remedy applied to one arm, and it worked without the flag-passing hand-off the
body above worries about — because there was no resolution step to protect, only
an `Exit` to remove. Two arms down by the same move (the record-cast twin in
`done/` was the first), which is evidence the unification is tractable
incrementally rather than as one change.

---

## 2026-09-04 (frankA) — the 25-shape sweep's divergence list is now EMPTY

The 2026-09-02 note left the sweep at 24/25 and said *"the ticket is not stale —
two lvalue parsers is still the design flaw — but the risk half of its case is
spent, and what is left is tidiness plus one loud refusal."*

**That one loud refusal is fixed** (`d9604ea59`,
[[bug-p-a-class-cast-cannot-index-a-default-property-as-an-assignment-target]]),
so the list reads:

| shape | |
| --- | --- |
| string-alias cast, indexed | fixed 2026-09-02 |
| class-cast default-property store | **fixed 2026-09-04** |

**25 of 25 target shapes now match fpc 3.2.2.**

### What that does to this ticket's case, stated plainly

The remaining argument is **purely** "two lvalue parsers is a design flaw" —
there is no measured divergence left to point at, and no known program that
compiles wrong because of the duplication. Whoever ranks this should rank it as
a refactor on its own merits and not on a defect backlog, because there isn't
one attached any more.

Two things that push slightly the other way and are worth weighing:

1. **The fix continued the pattern this ticket's own history calls tractable.**
   Like the two before it, it DELETED a special case rather than adding an arm:
   the class-cast target arm already hands its suffix to
   `ParseClassRecordSelectors`, and the bug was that the shared walker's
   default-property arm was incomplete. Three arms down by the same move, none
   of which needed the flag-passing hand-off the body worries about.
2. **The body's central worry has not been tested and is now cheaper to test.**
   It says the hand-off needs an "this is an assignment target" flag because the
   expression parser *"resolves a trailing `.name` as a field/method/property
   and may CALL it"*. In practice the shared walker answers that question itself
   — the NAMED-property arm peeks past the bracket group for `:=` and the
   DEFAULT arm now does too. If the walker can always decide locally, **the flag
   is not needed and the hand-off is smaller than this ticket assumes.** That is
   the single measurement that would most change the estimate, and it is one
   afternoon.

### The harness

The body says *"rebuild it from the shape list above"*. Still true, and there
are now three permanent rows in `test/` covering what used to be its findings:
`test_alias_cast_assign_target.pas`, `test_cast_default_property_target.pas`,
and the string-alias index test. Those are regression rows, not the sweep — the
sweep is still a before/after instrument and still worth rebuilding for the
refactor itself.
