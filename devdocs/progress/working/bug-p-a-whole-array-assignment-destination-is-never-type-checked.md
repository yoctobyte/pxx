---
track: P
prio: 45
type: bug
blocked-by: []
status: working
owner: frankB
created: 2026-09-06
found-by: frankB
summary: "`sa := s` and `c.SA := s` -- a managed string assigned to a WHOLE static array of AnsiString -- compile under pxx and SIGSEGV; fpc 3.2.2 refuses both. All four whole-array destination spellings (ident, field, deref, dynamic field) are accepted; two of the four crash. CAUSE IS NOT A MISSING ARM, IT IS THE FALLBACK: `AssignSideKind` returns False for an array-valued side because an array's TypeKind IS its element's kind, the AN_ASSIGN check short-circuits on that False, and the funnel's own header says a side it cannot type must fall back to the old ACCEPT -- so the bail that looks like a safety measure is what lets the store through. THIS IS A NARROWING and that is why it is a ticket: the funnel would start refusing programs the tree compiles today, and nobody has enumerated them. Found while building the census for refactor-p-is-this-node-a-whole-array-is-answered-in-four-places-with-four-lists, which established the neighbouring fact that a whole array has no TTypeKind to be typed as."
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
