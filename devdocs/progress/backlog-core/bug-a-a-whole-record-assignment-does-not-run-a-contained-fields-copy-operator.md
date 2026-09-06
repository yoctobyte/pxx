---
track: A
prio: 40
type: bug
blocked-by: []
summary: "MEASURED 2026-09-06 at 70fdf89165e1. Assigning a record that CONTAINS a field whose type declares `class operator Copy` does not run that field's Copy: `h2 := h1` where `THolder = record f: TFoo; k: Integer; end` and TFoo has Copy -- fpc 3.2.2 prints `Copy src.id=42`, pxx prints nothing and does a byte copy. ASYMMETRIC WITH THE OTHER TWO OPERATORS ON THE SAME SHAPE: Initialize and Finalize DO propagate into the field (both print twice, for h1.f and h2.f, under both compilers) because the scope desugar walks the field table and builds a field path; Copy is hooked at the IR assignment lowering instead, asks FindOpOverload(OPK_COPY, tyRecord, THolder), gets -1 because THolder itself declares nothing, and falls through to IR_COPY_REC. THE VALUE LOOKS CORRECT (42) so no expect_same row can see it -- Copy exists to do something OTHER than a byte copy (duplicate a handle, bump a refcount, deep-copy a buffer), so the two records silently SHARE whatever the field owned. RESOLVES THE `NOT ESTABLISHED` LINE in feature-pascal-management-operators-copy-and-addref: the two hooked assignment arms are NOT the whole population. Found by censusing 14 copy shapes against fpc; the other 13 agree (rows 1-8, 11, 14 fire in both; the dynamic-array rows are refused by feature-pascal-management-operators-nested-and-array and could not be measured). SECOND SITE, INDEPENDENT OF THE FIRST: a whole-STATIC-array assign `d := s` drops the element's OWN Copy (fpc fires twice, pxx never) while the controls `two := one` and `d[0] := s[0]` BOTH fire -- so the operator is dispatchable and the per-element path reaches it, and the whole-array assign is a block copy that never enters that path. Two sites, two mechanisms, only one nesting; a fix for either leaves the other. STATIC->DYNAMIC IS THE OPPOSITE AND IS CORRECT: it routes through the array constructor, which already dispatched operators before frankS's static-to-dynamic copy landed, and it FIRES, byte-identical to fpc. THE DISCRIMINATOR IS WHICH OPERATORS THE RECORD DECLARES, and it is why two sessions measured "the same" construct and disagreed: `var d: array of TR` is REFUSED when TR declares Initialize or Finalize and COMPILES when it declares only Copy or only AddRef. The diagnostic says "a record with a management operator", naming four operators where the rule uses two -- a Copy-only record satisfies that wording and compiles anyway. THE ASYMMETRY THAT CREATES SITE (1): the guard asks whether the ELEMENT record declares Initialize/Finalize, and a record that merely CONTAINS such a field declares none of its own, so it passes a refusal meant to be conservative and then silently skips the field. VERIFIED CORRECT, NOT A THIRD SITE: `b := a` between two dynamic arrays runs no operator in either compiler -- a reference copy, nothing to hook. ALL ROWS PRODUCE BYTE-IDENTICAL VALUES on both compilers, so no expect_same fixture over any of them can fail."
status: backlog
owner: unassigned
---

# A whole-record assignment does not run a contained field's `Copy` operator

## Repro

```pascal
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TFoo = record
    id: Integer; pad1, pad2, pad3: Int64;
    class operator Initialize(var a: TFoo);
    class operator Finalize(var a: TFoo);
    class operator Copy(constref src: TFoo; var dst: TFoo);
  end;
  THolder = record f: TFoo; k: Integer; end;
...
procedure P;
var h1, h2: THolder;
begin
  h1.f.id := 42;
  h2 := h1;              { <-- fpc runs TFoo.Copy here; pxx does not }
end;
```

| line | fpc 3.2.2 | pxx |
| --- | --- | --- |
| `Init` (h1.f, h2.f) | ×2 | ×2 |
| **`Copy src.id=42`** | **yes** | **no** |
| `h2.f.id` | 42 | 42 |
| `Fin` (both) | ×2 | ×2 |

Everything agrees except the operator call — **including the resulting value**,
which is why this cannot be caught by an output comparison.

## Why the value being right is the problem

`Copy` exists precisely so that duplicating a record is *not* a byte copy: it
duplicates a handle, bumps a refcount, deep-copies a buffer. Skipping it leaves
both records pointing at whatever the field owned, so the defect surfaces later
as a double free, a shared mutation or a refcount that never reaches zero —
arbitrarily far from the assignment, and never as a wrong field value at the
assignment itself.

**Match the assertion class to the defect class:** a fixture for this must make
the operator PRINT (or count allocations), never compare the copied value.

## The asymmetry, which is where the fix should look

Three operators, one containing record, two different mechanisms:

- `Initialize`/`Finalize` reach the field because the **scope desugar walks the
  field table** and synthesises a field path (`WrapManagementOpsRange`, and the
  `UFldTk`/`UFldIsArray` handling `test_mgmt_operators_field_refused` documents).
- `Copy` is hooked at the **IR assignment lowering** (`ir.inc:13403`, `:13817`,
  via `IRRecCopyOpCall`), which asks `FindOpOverload(OPK_COPY, tyRecord, recId)`
  for the record **being assigned**. `THolder` declares no Copy, so the lookup
  returns -1 and the plain `IR_COPY_REC` is emitted.

So one concept is served by two mechanisms with different reach — the smell
`devdocs/dev/normalise-dont-special-case.md` names, and the reason the sibling
arm stayed broken when the first was taught. A fix that teaches the assignment
hook to walk fields should be checked against whether the desugar can own both
instead.

## Interim option, NOT taken here

A refusal (as for the ≤8-byte by-value case) would convert a silent wrong answer
into a diagnostic. **It is not applied because it would be a regression for code
using only `Initialize`/`Finalize`:** a record containing a managed record is
accepted today and works correctly for those two, and the refusal would have to
be narrowed to "contains a field whose type declares Copy" to avoid that. That
narrowing is cheap, but it changes what compiles, so it wants a corpus
measurement first rather than being folded into a bug report.

## Scope of the census

14 copy shapes, measured against fpc 3.2.2. Rows that agree (Copy fires in
both): local:=local, global:=local, static array element, global array element,
record field destination, `var` parameter destination, function `Result`
destination, local:=function result, global holder field, `with` block. Rows not
measurable: the three dynamic-array shapes, refused by
[[feature-pascal-management-operators-nested-and-array]]. Diverging: this one.

## A SECOND, INDEPENDENT SITE: a whole-ARRAY assignment drops the element's own `Copy`

Measured 2026-09-06 at `cf01faf5107e`, prompted by frankS reporting their
static-array-to-dynamic-array copy reaching this defect. **Their localisation
does not hold and the correction matters, because it changes what a fix has to
cover.** Reproduced independently rather than taken from the report:

```pascal
var s, d: array[0..1] of TR;   { TR ITSELF declares class operator Copy }
...
two := one;        { CONTROL 1 — scalar record assign }
d[0] := s[0];      { CONTROL 2 — element to element }
d := s;            { ROW A     — whole static array assign }
```

| | fpc 3.2.2 | pxx |
| --- | --- | --- |
| CONTROL 1 `two := one` | fires | **fires** |
| CONTROL 2 `d[0] := s[0]` | fires | **fires** |
| ROW A `d := s` | fires ×2 | **never** |
| resulting values | 11 22 | 11 22 |

**The two controls are what make this readable.** They prove the operator is
dispatchable and that the per-element assign path reaches it, so ROW A is not a
missing overload or an unresolvable record — **a whole-array assignment does not
go through the per-element path at all.** It is a block copy, and the element's
own `Copy` is bypassed even though nothing about the element is nested.

**So this is NOT downstream of the contained-field defect above, and fixing the
record-assign path will NOT close it.**

### CORRECTION — I accused a peer of a misreading and I was wrong

An earlier revision of this section said frankS's contradicting row was "most
likely an fpc result attributed to pxx while running both". **That was a
speculative attribution of error, it was wrong, and it is withdrawn.** Both
measurements were correct and they were of DIFFERENT records:

| record declares | `d, s: array[0..1] of TR` (static→static) | `s: array[0..1]; d: array of TR` (static→dynamic) |
| --- | --- | --- |
| **`Copy` only** | **Copy DROPPED** (this site) | **Copy FIRES**, matches fpc |
| `Initialize`/`Finalize` too | Copy dropped | **declaration REFUSED** |

frankS's record declared `Copy` alone, so their static→dynamic row compiled and
fired. Mine declared `Initialize`, `Finalize` and `Copy`, so the same shape was
refused at the DECLARATION and I never reached the assignment — I then measured
the static→static form, which is a different construct, and read the two as
contradicting.

**Both rows stand. The disagreement was the finding**: it is what separated the
block-copy path from the constructor path, and neither of us could have found
that alone. The lesson is not about trusting a peer's number — it is that "the
same construct" was doing unstated work in both directions.

Recorded rather than silently edited, because the wrong sentence was pushed and
someone reading only the summary would carry it.

**Two sites, two mechanisms, and only one of them is nesting:**

1. `y := x` where the record CONTAINS a `Copy`-operator field — the per-element
   path runs, the OUTER record has no overload, the contained field is never
   walked. (The original finding above.)
2. `d := s` over an array — the per-element path is not run at all, so even a
   non-nested element with its own `Copy` is skipped.

A fix aimed only at (1) leaves (2); a fix aimed only at (2) leaves (1).

### The refusal is keyed on `Initialize`/`Finalize`, NOT on "a management operator"

Measured one operator at a time, `var d: array of TR`:

| `TR` declares | `array of TR` |
| --- | --- |
| `Copy` only | **compiles** |
| `AddRef` only | **compiles** |
| `Initialize` only | refused |
| `Finalize` only | refused |

Only the two that need a synthesised per-element loop at scope entry and exit
trip it, which is correct. **The diagnostic was not** — it said *"a record with a
management operator"*, naming four operators where the rule uses two, so a
`Copy`-only record satisfied the stated rule and compiled anyway.

### The class: a predicate's NAME leaking into a user-facing string

frankS's framing, and it is sharper than "the message was vague":

> A predicate's name leaking into a diagnostic is a different risk class from
> the same name leaking into a call site, because a call site has the body one
> jump away and a diagnostic has nothing.

**Nothing here lied and nothing was vague.** `RecHasManagementOp` was a true
sentence about a predicate that tests two operators; the message quoted it; a
reader concluded, correctly from that sentence, that the door was shut for all
four. The error was checkable only by reading the predicate BODY — and a
diagnostic's reader is precisely the person who cannot. **A refusal message is
the only spelling of the rule anyone outside the code ever sees**, so an
80%-accurate internal name stops being a convenience the moment it escapes into
one and becomes documentation.

This is `the name is not the thing` from CLAUDE.md, with the extra clause that
the blast radius depends on where the name escapes to.

**A second member of the class, one level down** (frankS, `cd3709f60`): a
three-clause guard that fired and named its SUBJECT but not WHICH CLAUSE. They
re-read the arm three times, reasoned to the wrong half, and spent a build
correctly plumbing a destination encoding that was never the problem — the
source had been flattened to 2-D. What settled it in one build was printing the
guard's own inputs into the diagnostic: `ndims=2 elemdyn=0 dstrowlen=3`. So the
playbook's *do not theorise about an inferred value, print it* applies to **a
guard's inputs**, not only to a type.

**The three sibling refusals in `WrapManagementOpsRange` are deliberately NOT
re-worded** (agreed with frankS, who is not near that code and is not taking
them). They say "a field of a record with a management operator" and carry the
same imprecision. Only the one that provably misled someone was fixed. They are
the population for the next instance: **fixing all four speculatively would make
the class invisible**, and if one of them misleads someone the report will name
it. Do not tidy them.

**FIXED, since it is what caused the misreading above** rather than merely
describing it. The predicate was named `RecHasManagementOp` and tests
`OPK_INITIALIZE`/`OPK_FINALIZE` only; it is now `RecHasScopeManagementOp` and
the message names those two operators, says why (they need the per-element
loop), and states that `Copy` and `AddRef` are unaffected. Behaviour is
unchanged — verified one operator at a time, before and after — and the two
fixtures asserting this refusal grep the ticket SLUG, not the prose, so they are
untouched.

This also corrects an earlier note here. It said the guard "asks whether the
ELEMENT record has a management operator, and a record that merely contains one
has none of its own". The second half stands and explains site (1); **the first
half was imprecise** — it asks about `Initialize`/`Finalize`, which is why a
`Copy`-only element reaches the dynamic path at all and why frankS's row could
be measured while mine could not.

### A shape that is CORRECT, checked so it is not mistaken for a third site

`b := a` for two dynamic arrays runs no operator in **either** compiler, and
`b[0] := 999` leaves `a[0] = 999` in both: a dyn-array assignment is a reference
copy, so there is no copy for an operator to hook. Byte-identical. frankS raised
it as a possible third site and judged it correct; confirmed against fpc here.

**Every row here produces byte-identical values on both compilers** (11 22, and
11/1 22/2 for the nested form). No `expect_same` fixture over any of these
programs can fail. frankS's decision not to add a row asserting today's
behaviour is right and is worth restating: a test encoding the missing call is a
regression assertion wearing the shape of a control, and it goes red the day the
defect is fixed.
