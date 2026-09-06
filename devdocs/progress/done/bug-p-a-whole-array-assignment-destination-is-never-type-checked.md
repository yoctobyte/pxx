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
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit fecdfe6dc.

### The frontend corpora, measured after the fix landed — and the number is THIN

Rust and Zig go through this funnel; only C and NilPy are excluded. The
narrowing landed without them measured, so they were measured immediately after
rather than left as a blank someone else would have to find.

**691 non-Pascal sources, 596 compiled to the end, `refuse=0`. Read that number
carefully, because it splits into one useful half and one vacuous one:**

| population | whole-array destinations | refused |
| --- | --- | --- |
| Rust, Zig, BASIC, Erlang, Fortran, Algol, LOLCODE — the refusal **applies** | **12** | 0 |
| C and NilPy — `CProgramMode` / `PyProgramMode` **exclude** them from this check | 2169 | 0 |

The second row is a zero **by construction** and is not evidence of anything: it
would read 0 with the rule set to refuse everything. It is recorded only so
nobody re-derives it and mistakes it for coverage.

The first row is the one that counts and **twelve is a thin aperture**. It is
not a clear for those frontends; it is "no signal, from here". The Rust and Zig
corpora simply do not assign whole arrays much. Ada has no corpus in this tree
at all — zero sources, so its cell is unmeasured rather than clean.

`lib/` units that no fixture reaches are still unmeasured, for the reason
frankA's case-pair census records about the same population: a unit nothing
imports contributes nothing and is indistinguishable here from a clean one.

### Was the census population the tree it claims? Asked and answered from the reflog

Raised by frank-coordinator, and it is the right question to ask of any number a
narrowing was landed on: CLAUDE.md's mid-sweep hazard is that a pull moves the
population under a running harness, and **a corrupted measurement that survives
the question you happened to ask is indistinguishable from a clean one.**

The checkout's reflog settles it, and it is the instrument that fails
differently from a file mtime:

| | |
| --- | --- |
| HEAD moved to `a0fef585c` (the instrument's sync) | 19:00:34 |
| census run 1 — the 49 false refusals | 19:02:32 → 19:05:13 |
| census run 2 — the 1445 / refuse=0 | 19:08:44 → 19:11:59 |
| next HEAD move (`f8c2bbf72`, a LOCAL commit, no pull) | 19:16:32 |
| next PULL (`rebase (start)`) | 19:24:58 |

**No pull, no rebase, no HEAD move inside either window** — the nearest one is
eight minutes before the first and thirteen minutes after the last. Corroborated
independently: every mtime under the test and example trees newer than 18:55 is
19:25:48, the rebase, so nothing in the population moved while it was being
read.

**What the census tree is NOT is the tree the fix landed on.** Six corpus files
changed between `a0fef585c` and the fix — four of them other agents' — so the
number is honest about `a0fef585c` and silent about the delta. That is a real
gap and it is cheap to close, so it was: re-run over exactly those six,
`seen=16 keep=16 refuse=0`. The only REFUSE lines in it are the four from this
ticket's own refusal fixture, which is the file that must not compile, and it is
also why five of the six reach a TOTAL rather than all six.
