---
track: A
prio: 40
type: bug
blocked-by: []
summary: "MEASURED 2026-09-06 at 70fdf89165e1. Assigning a record that CONTAINS a field whose type declares `class operator Copy` does not run that field's Copy: `h2 := h1` where `THolder = record f: TFoo; k: Integer; end` and TFoo has Copy -- fpc 3.2.2 prints `Copy src.id=42`, pxx prints nothing and does a byte copy. ASYMMETRIC WITH THE OTHER TWO OPERATORS ON THE SAME SHAPE: Initialize and Finalize DO propagate into the field (both print twice, for h1.f and h2.f, under both compilers) because the scope desugar walks the field table and builds a field path; Copy is hooked at the IR assignment lowering instead, asks FindOpOverload(OPK_COPY, tyRecord, THolder), gets -1 because THolder itself declares nothing, and falls through to IR_COPY_REC. THE VALUE LOOKS CORRECT (42) so no expect_same row can see it -- Copy exists to do something OTHER than a byte copy (duplicate a handle, bump a refcount, deep-copy a buffer), so the two records silently SHARE whatever the field owned. RESOLVES THE `NOT ESTABLISHED` LINE in feature-pascal-management-operators-copy-and-addref: the two hooked assignment arms are NOT the whole population. Found by censusing 14 copy shapes against fpc; the other 13 agree (rows 1-8, 11, 14 fire in both; the dynamic-array rows are refused by feature-pascal-management-operators-nested-and-array and could not be measured). SECOND SITE 2026-09-06, INDEPENDENT OF THE FIRST: a whole-ARRAY assignment `d := s` over `array[0..1] of TR` drops the element's OWN Copy -- fires twice under fpc, never under pxx -- while the controls `two := one` and `d[0] := s[0]` BOTH fire, which proves the operator is dispatchable and the per-element path reaches it, so the whole-array assign is a block copy that never runs that path. NOT downstream of the contained-field defect and NOT closed by fixing the record-assign path: two sites, two mechanisms, only one of them nesting. This CORRECTS frankS's report that the array row fires under pxx and would therefore close for free (an fpc result read as a pxx one); recorded because that conclusion would have left this site with nobody holding it. The static->DYNAMIC form cannot be measured at all -- refused by feature-pascal-management-operators-nested-and-array, whose guard asks whether the ELEMENT record has an operator, which is exactly why the CONTAINED-field case slips through it. All rows produce byte-identical values on both compilers."
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
record-assign path will NOT close it.** frankS's report stated the opposite —
that `array[0..1] of TR` with `TR` declaring `Copy` fires under pxx, and
therefore only the CONTAINED field is dropped and their path would close for
free once the record-assign path is fixed. Measured here, that row fires under
fpc and **never** under pxx; the most likely reading is an fpc result attributed
to pxx while running both. Recorded because the conclusion drawn from it — "no
edit needed on my side" — would have left this site unfixed with nobody holding
it.

**Two sites, two mechanisms, and only one of them is nesting:**

1. `y := x` where the record CONTAINS a `Copy`-operator field — the per-element
   path runs, the OUTER record has no overload, the contained field is never
   walked. (The original finding above.)
2. `d := s` over an array — the per-element path is not run at all, so even a
   non-nested element with its own `Copy` is skipped.

A fix aimed only at (1) leaves (2); a fix aimed only at (2) leaves (1).

**Not measurable for a dynamic destination.** `s: array[0..1] of TR;
d: array of TR` is refused outright — *"a dynamic or multi-dimensional array of
a record with a management operator"* — so the static→dynamic form of ROW A
cannot be measured until
[[feature-pascal-management-operators-nested-and-array]] lands. Note the
asymmetry that lets the CONTAINED-field case through the same refusal: the guard
asks whether the ELEMENT record has a management operator, and a record that
merely contains one has none of its own.

**Every row here produces byte-identical values on both compilers** (11 22, and
11/1 22/2 for the nested form). No `expect_same` fixture over any of these
programs can fail. frankS's decision not to add a row asserting today's
behaviour is right and is worth restating: a test encoding the missing call is a
regression assertion wearing the shape of a control, and it goes red the day the
defect is fixed.
