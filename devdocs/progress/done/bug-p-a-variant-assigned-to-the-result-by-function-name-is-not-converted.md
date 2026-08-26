---
slug: bug-p-a-variant-assigned-to-the-result-by-function-name-is-not-converted
title: "A Variant assigned to the function result by FUNCTION NAME is not converted — the slot address is stored"
track: P
prio: 65
type: bug
blocked-by: []
status: done
owner: opus5-frank1
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

# Outcome — 2026-08-26

Fixed by DELETING the special case, not by teaching it about Variants.

## Root cause

`compiler/pasparser_stmt.inc`, the own-name result-assignment arm (and its twin
for functions whose name lexes as a keyword — `Read`, `Write`, `Readln`,
`Writeln`). Both had the same two-branch shape:

```pascal
if CurTok.Kind = tkAssign then
begin
  Expect(tkAssign, ':=');
  valNode := AllocNode(AN_IDENT);            { <-- no ASTTk }
  ASTIVal[valNode] := Procs[CurProc].RetSymIdx;
end
else
begin
  valNode := ParseLValueAST(Procs[CurProc].RetSymIdx, TokPos - 2);
  Expect(tkAssign, ':=');
end;
```

The `.field` / `[i]` / `^` shapes went through `ParseLValueAST` and were fine.
The BARE `F := expr` shape took the shortcut and hand-built an `AN_IDENT` with
**no `ASTTk` stamped**. Everything downstream that reads the assignment
target's type then had nothing to read, so no conversion was selected and the
right-hand side was stored raw — for a Variant source, the slot ADDRESS.

`Result := expr` was never affected because `Result` is a real symbol
(`AllocVar('Result', …)`), so it goes through the ordinary identifier path and
gets its type stamped like any other lvalue. Two spellings of one statement,
one of them bypassing the substrate.

## The fix

Both arms now call `ParseLValueAST` unconditionally. The shortcut is gone.
`normalise-dont-special-case.md`: the wrong answer was not "Variants are
missing here", it was "this arm builds its own node instead of asking the
routine that builds them".

Net: **twelve lines removed, one call moved.**

## Verification

Six rows against fpc 3.2.2 -Mobjfpc -O1, all now identical where four were
wrong before:

| row | pxx before | pxx after / fpc |
| --- | --- | --- |
| `ByName := v` → Int64 | 4350216 (an address) | 5000000000 |
| `Result := v` → Int64 | 5000000000 | 5000000000 |
| `FromGlobal := g` → Int64 | 2 | 5000000000 |
| `AsDouble := v` → Double | 4350248.0000 | 2.5000 |
| `AsStr := v` → AnsiString | *(empty)* | hey |
| `AsBool := v` → Boolean | TRUE (by luck) | TRUE |

Shapes varied before closing, as the ticket asked: a nested function assigning
its own result by name, `Exit(v)` with a Variant operand and an ordinal result,
a record result via `F.field :=`, a dynamic-array result via `SetLength(F, n)`
and `F[i] :=`, ShortString and Char results, a global-variant source as well as
a parameter. All match FPC.

The keyword-named twin was checked separately: `test_virtual_keyword_result`
and `lib_textreadnumtok` (which is built on `Read := …`) both still pass.

* `tools/gate.sh quick` GREEN, self-host converged after 1 round — and the
  self-host is itself the widest test this change has, since compiler.pas
  assigns its results by function name throughout.
* `tools/run_pascal_conformance.sh`: **346 pass, 0 fail**, 170 skip, 34
  auto-gated (of 550) — unchanged.
* `tools/run_fgl_corpus.sh` against real FPC 3.2.2 `fgl.pp`: 6 pass, 0 fail,
  1 skip — unchanged.
* The new test and `test_wide_int_boxes_into_a_variant` both ALL OK on x86-64,
  i386, arm32 and aarch64.

## Files

* `compiler/pasparser_stmt.inc` — the shortcut deleted in both own-name arms.
* `test/test_result_by_function_name_converts.pas` — new, 15 rows.
* `test/test_wide_int_boxes_into_a_variant.pas` — its `RoundTripParam` goes
  back to the direct `RoundTripParam := d` it was written with, as this
  ticket's acceptance required.
* `Makefile` — the new test wired into `test-core`.

## Log
- 2026-08-26 — resolved, commit 240f4ecb7.
