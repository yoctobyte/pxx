---
track: P
prio: 45
type: bug
blocked-by: []
status: done
owner: frankB
created: 2026-09-06
found-by: frankB
summary: "`sa := s` and `c.SA := s` -- a managed string assigned to a WHOLE static array of AnsiString -- compiled under pxx and SIGSEGV'd; fpc 3.2.2 refuses both. All four whole-array destination spellings (ident, field, deref, dynamic field) were accepted; two of the four crashed. CAUSE IS NOT A MISSING ARM, IT IS THE FALLBACK: `AssignSideKind` returns False for an array-valued side because an array's TypeKind IS its element's kind, the AN_ASSIGN check short-circuits on that False, and the funnel's own header says a side it cannot type must fall back to the old ACCEPT -- so the bail that looks like a safety measure is what let the store through. FIXED 2026-09-06 with the narrowing MEASURED FIRST: PXXDBG=a.wholearr counted the population over 2109 files, 1834 of which compiled to the end, 1445 whole-array destinations, and the rule that landed refuses ZERO of them. THE TICKET'S OWN PRESCRIPTION WAS THE WRONG WAY ROUND and the census is what said so: 'refuse a right-hand side that is not itself an array of a compatible shape' refused 49 legal sites in twelve files and none of the defect, because no reader in the tree can say 'this expression's VALUE is an array' for a call result or a fixed row out of a dynamic array. The rule asks the opposite question -- refuse only what can be POSITIVELY typed as a NON-array -- which is the funnel's own documented policy. NAMED BLANK, not a clear: a FIELD or DEREF right-hand side is still accepted, because `RecFieldIsArray` returns False both for a non-array field and for one it did not find and nothing separates those."
---

# A whole-array assignment destination is never type-checked

Measured 2026-09-06 at compiler `aa8f3c3b4b68` against fpc 3.2.2.

```pascal
type TSA = array[0..2] of AnsiString;
     PSA = ^TSA;
     TC = class SA: TSA; DA: array of AnsiString; end;
var sa: TSA; p: PSA; c: TC; s: AnsiString;
```

| statement | pxx | fpc 3.2.2 |
| --- | --- | --- |
| `sa := s` | **accepted, SIGSEGV** | `Incompatible types: got "AnsiString" expected "TSA"` |
| `c.SA := s` | **accepted, SIGSEGV** | refused |
| `p^ := s` | accepted, exit 0 | refused |
| `c.DA := s` | accepted, exit 0 | refused |

Four spellings, one behaviour: the check never fires. The two that crash are the
ones where the store lands on managed-string slots.

## Why the check cannot fire, which is the part that is not obvious

`AssignSideKind` types one side of an assignment. **An array's `TypeKind` IS its
element's kind**, so an array-valued side cannot be described by a kind at all
and the function returns False. The funnel is

```pascal
if AssignSideKind(lhs, dstTk) and AssignSideKind(rhs, srcTk) and
   AssignKindsIncompatible(dstTk, srcTk) then Error(...)
```

so a False short-circuits the whole rule. `AssignSideKind`'s own header states
this is deliberate — *"a shape it cannot type must fall back to the old accept —
a false REJECT of working code is a worse defect than the false accept being
fixed here"* — and it is right about the trade in general. It is wrong for this
shape specifically, because there is no legal assignment of a scalar to a whole
array for the accept to protect.

**So the bail that reads as a safety measure is the thing letting the store
through**, and adding an arm to `AssignSideKind` cannot fix it: there is no
`TTypeKind` for "array of AnsiString" to return.

## What the fix has to look like

A rule ABOVE the kind funnel, at the same AN_ASSIGN site, that asks
`ASTNodeIsWholeArray(lhs)` and refuses a right-hand side that is not itself an
array of a compatible shape — the same place and shape as the fixed→dynamic
guard that already sits there for the pair the kind cannot express.

Note the fixed→dynamic guard is the precedent in every respect: same site, same
reason (*"both sides are tyInteger, because an array symbol's TypeKind is its
ELEMENT's kind, so the check above sees a matching pair and waves it through"*),
and it was landed as a named refusal with a follow-on for the copy.

## Why it was not landed with the census

**It is a narrowing.** The funnel would start refusing programs that compile
today, and the population is unknown — `lib/**`, the corpora, four frontends.
Two shapes must survive by name, both already documented one screen up in
`ir.inc`: `d := e` (dyn to dyn) and `t := o` (an open-array PARAMETER to a
dynamic array, which fpc rejects and we accept deliberately). A parameter's
recorded length is untrustworthy in both directions because `AllocParam` stamps
`ArrLen := 1000`, so the parameter row is the one to measure first.

## Neighbour

[[refactor-p-is-this-node-a-whole-array-is-answered-in-four-places-with-four-lists]]
is where this was found and it carries the census: three questions, not four
answers to one, and a whole array has no kind to be typed as.

## RESOLVED 2026-09-06 — and the census is the finding, not the fix

The fix is four lines above the kind funnel in `ir.inc`. Everything worth
recording is in what the measurement said about the fix this ticket prescribed.

### The instrument: `PXXDBG=a.wholearr`

One line per assignment whose destination is a whole array, tagged `keep` or
`REFUSE` by the candidate rule, plus a `TOTAL seen=/keep=/refuse=` denominator
so a run that prints no REFUSE lines can say which kind of silent it is.

**The channel calls the rule; it does not describe it.** `DbgWholeArrRhsShaped`
is the function the refusal calls, so `refuse=N` is exactly the number of sites
the narrowing breaks and there is no second implementation to drift away from
the measured one.

Placed ABOVE the fixed->dynamic guard on purpose. That guard REWRITES the
right-hand side into an element-list constructor, so a channel below it would
report every `d := s` as an array constructor and count its neighbour's fix as
this ticket's population.

### What the census said, and it inverted the prescription

| | sites | |
| --- | --- | --- |
| attempted | 2109 | every Pascal fixture under the test tree plus `examples/`, `--threadsafe` |
| compiled to the end | 1834 | the 275 that did not report nothing, and that zero means nothing |
| whole-array destinations | 1445 | the denominator |

**Candidate 1 — this ticket's own prescription**, *"refuse a right-hand side
that is not itself an array of a compatible shape"*: **49 false refusals in
twelve files, zero instances of the defect.**

| RHS node kind | sites | what it is |
| --- | --- | --- |
| `AN_CALL` | 35 | a function returning a STATIC array |
| `AN_INDEX` | 6 | a fixed ROW out of a dynamic array — the index has not selected an element |
| `AN_CALL_IND` / `AN_INTF_CALL` | 4 | the same through a procedural value or an interface |
| `AN_DEFAULT` | 3 | `Default(T)` on an aggregate |
| `AN_INT_LIT` | 1 | `Default(TDyn)`, which is already lowered to a zero literal by the time the rule runs |

The reason is structural and is the part worth keeping: **there is no reader in
the tree that can say "this expression's VALUE is an array"** for a call result
or a row, so a rule phrased that way refuses everything it cannot see. It is the
same defect as the one being fixed, pointed the other way.

**Candidate 2 — what landed**: refuse only what can be POSITIVELY typed as a
non-array. That is `AssignSideKind`'s own documented policy applied to arrays
instead of kinds, and an IDENT is the one spelling where "not an array" is a
recorded flag on a symbol that exists rather than a False that might mean "not
found". **Cost over the same 1445: zero.** It is exactly the four rows reported,
whose right-hand side is an AnsiString identifier in all four.

### The named blank, which is not a clear

A **FIELD** or **DEREF** right-hand side is still accepted. `sa := c.Name`
therefore still compiles and still crashes. `RecFieldIsArray` returns False both
for a field that is not an array and for a field it did not find, and no reader
separates those — a refusal there fires on an unresolved record, which is a
false reject of working code. Closing that blank needs a field-exists reader
covering builtin and user records alike, which is
[[refactor-p-is-this-node-a-whole-array-is-answered-in-four-places-with-four-lists]]'s
territory.

Also unmeasured: `lib/` units no fixture reaches, and the Rust/Zig/BASIC/Ada
corpora, which DO go through this funnel (only C and NilPy are excluded).

### The fixtures, and why one of them is the interesting one

`test_a_whole_array_destination_refuses_a_scalar.pas` must not compile; the
Makefile asserts the diagnostic TEXT and asserts that all **four** spellings are
reported, because the check recovers and a fatal one would have certified three
of them untested.

`test_a_whole_array_destination_takes_every_shape_the_census_found.pas` is the
positive control for the narrowing and **every row is a right-hand-side node
kind the census actually saw** — not one invented. Rows 6 through 9 are the four
families candidate 1 would have refused; if any of them stops compiling, the
rule has been rephrased back into the shape the census rejected. Twelve of its
thirteen rows are byte-identical to `fpc 3.2.2 -Mobjfpc`. The thirteenth is row
4, `t := o`, an open-array PARAMETER assigned to a dynamic array, which fpc
refuses (`Incompatible types: got "{Open} Array Of LongInt"`) and we accept
deliberately — measured, not assumed, and nothing in the rule asks a length
because `AllocParam` stamps `ArrLen := 1000` on every array parameter.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
