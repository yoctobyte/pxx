---
track: A
prio: 40
type: bug
blocked-by: []
summary: "MEASURED 2026-09-06 at 70fdf89165e1. Assigning a record that CONTAINS a field whose type declares `class operator Copy` does not run that field's Copy: `h2 := h1` where `THolder = record f: TFoo; k: Integer; end` and TFoo has Copy -- fpc 3.2.2 prints `Copy src.id=42`, pxx prints nothing and does a byte copy. ASYMMETRIC WITH THE OTHER TWO OPERATORS ON THE SAME SHAPE: Initialize and Finalize DO propagate into the field (both print twice, for h1.f and h2.f, under both compilers) because the scope desugar walks the field table and builds a field path; Copy is hooked at the IR assignment lowering instead, asks FindOpOverload(OPK_COPY, tyRecord, THolder), gets -1 because THolder itself declares nothing, and falls through to IR_COPY_REC. THE VALUE LOOKS CORRECT (42) so no expect_same row can see it -- Copy exists to do something OTHER than a byte copy (duplicate a handle, bump a refcount, deep-copy a buffer), so the two records silently SHARE whatever the field owned. RESOLVES THE `NOT ESTABLISHED` LINE in feature-pascal-management-operators-copy-and-addref: the two hooked assignment arms are NOT the whole population. Found by censusing 14 copy shapes against fpc; the other 13 agree (rows 1-8, 11, 14 fire in both; the dynamic-array rows are refused by feature-pascal-management-operators-nested-and-array and could not be measured)."
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
