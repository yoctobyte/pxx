---
slug: bug-p-a-variant-assigned-to-the-result-by-function-name-is-not-converted
title: "A Variant assigned to the function result by FUNCTION NAME is not converted — the slot address is stored"
track: P
prio: 65
type: bug
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-26
summary: "`F := v` with v: Variant and F returning Int64/Double/AnsiString stores the variant SLOT ADDRESS instead of converting. `Result := v` -- the same line, the other spelling -- converts correctly. Every target including x86-64; fpc 3.2.2 gets all of it right. Found while closing bug-a-an-int64-assigned-to-a-variant-truncates-to-32-bits-on-i386-and-arm32."
---

# Measured, 2026-08-26, pinned compiler, x86-64

```pascal
{$mode objfpc}
program vres3;
var g: Variant;
function ByName(v: Variant): Int64;      begin ByName := v; end;
function ByResult(v: Variant): Int64;    begin Result := v; end;
function FromGlobal: Int64;              begin FromGlobal := g; end;
function AsDouble(v: Variant): Double;   begin AsDouble := v; end;
function AsStr(v: Variant): AnsiString;  begin AsStr := v; end;
function AsBool(v: Variant): Boolean;    begin AsBool := v; end;
begin
  g := 5000000000;
  WriteLn(ByName(g)); WriteLn(ByResult(g)); WriteLn(FromGlobal);
  g := 2.5;   WriteLn(AsDouble(g):0:4);
  g := 'hey'; WriteLn(AsStr(g));
  g := True;  WriteLn(AsBool(g));
end.
```

| row | pxx | fpc 3.2.2 |
| --- | --- | --- |
| `ByName := v` (Int64) | **4350216** — an address | 5000000000 |
| `Result := v` (Int64) | 5000000000 | 5000000000 |
| `FromGlobal := g` (Int64, global source) | **2** | 5000000000 |
| `AsDouble := v` (Double) | **4350248.0000** | 2.5000 |
| `AsStr := v` (AnsiString) | **empty** | hey |
| `AsBool := v` (Boolean) | TRUE | TRUE |

Measured identically on x86-64, i386, arm32 and aarch64, so this is not a
backend gap — the conversion is missing before codegen. The Boolean row agrees
by luck (a non-zero address is truthy), which is exactly the kind of accidental
agreement that keeps a defect hidden.

# Why this matters more than the row count suggests

Two spellings of the same statement, one correct and one silently wrong, in the
dialect where the function-name spelling is the OLDER and more common one — it
is what every non-objfpc unit in the corpus writes. Nothing errors; the caller
receives an address that looks like a plausible number.

# Where to look

`Result := v` reaching the right answer means the Variant-to-ordinal conversion
exists and is applied on one assignment path and not the other. The two paths
converge in the parser's assignment lowering, so the likely shape is that the
function-name form is recognised as "assign to the result slot" somewhere that
bypasses the type-directed coercion the ordinary target lookup performs.

`root-cause-over-microfix.md`: find the ONE place the two spellings diverge
rather than adding a Variant special case to the function-name arm. Then vary
the shape — a nested function, a function whose result type is a record or a
class, an `Exit(v)`, and the C/Rust/Zig frontends' own result-assignment
spellings, all of which should be reached by the same fix if it is in the right
place.

# Acceptance

- All six rows above match fpc 3.2.2 on x86-64, i386, arm32 and aarch64.
- `Exit(v)` with a Variant operand and an ordinal result type agrees too.
- `test/test_wide_int_boxes_into_a_variant.pas`'s `RoundTripParam` goes back to
  the direct `RoundTripParam := d` it was written with, and its note is deleted.
- Self-host byte-identical.
