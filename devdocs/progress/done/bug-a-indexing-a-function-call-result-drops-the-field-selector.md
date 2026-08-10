---
track: A
prio: 55
type: bug
blocked-by: []
status: done
owner: claude-A
---

# Indexing a function CALL RESULT: `.field` after `[i]` is silently dropped

- **Type:** bug (silent wrong value) — **Track A**
- **Found:** 2026-08-10, in passing while fixing
  [[bug-a-nd-array-function-result-indexes-the-wrong-slot]]. Not caused by it —
  `pinned` could not compile the shape at all, because an array-of-record
  result did not work there.

```pascal
type TRec  = record a, b, c: Integer; end;
     TArrR = array[0..1] of TRec;
function MkR: TArrR;
begin MkR[0].a:=1; MkR[0].b:=2; MkR[0].c:=3;
      MkR[1].a:=4; MkR[1].b:=5; MkR[1].c:=6; end;
var v: TArrR;
begin
  v := MkR;
  WriteLn(v[0].a,' ',v[0].b,' ',v[0].c,' ',v[1].a,' ',v[1].b,' ',v[1].c);
  WriteLn(MkR[0].a,' ',MkR[0].b,' ',MkR[0].c,' ',MkR[1].a,' ',MkR[1].b,' ',MkR[1].c);
end.
```

| | via a VARIABLE | direct on the CALL |
| --- | --- | --- |
| FPC | `1 2 3 4 5 6` | `1 2 3 4 5 6` |
| pxx | `1 2 3 4 5 6` | **`1 1 1 4 4 4`** |

The subscript is applied; the **field selector after it is dropped entirely**,
so every field of `MkR[i]` answers field `a`. No diagnostic.

## The real shape: one concept, five paths, three of them missing

`f(...)[i]` is reachable through several receivers and each was wired
separately. Measured at `5f8e1ccce`:

| expression | result |
| --- | --- |
| `MkS[2]` — `function MkS: string` | **works** |
| `MkRec.a` — record result, field only, no subscript | **works** |
| `MkR[i].field` — fixed array OF RECORD result | **compiles, wrong value** |
| `MkA[i]` — fixed array of a SCALAR result | `error: unexpected token` |
| `MkD[i]` — DYNAMIC array result | `error: unexpected token` |
| `MkR[i,j].field` — N-D array result | `error: unexpected token` |

`MkA()[i]` / `MkD()[i]` (explicit empty parens) fail identically, so it is not
the bare-own-name spelling.

This is the `normalise-dont-special-case` shape: the string arm and the
record-field arm each learned to take a call as a receiver; the array-element
arms did not, and the one that half-did loses the selector. **Do not add a sixth
arm** — find the single place a postfix chain is built over a primary and make a
call result an ordinary receiver there, then let all six spellings fall out.
See [[project_nilpy_lvalue_vs_selector_path_must_both_know]] for the same shape
one frontend over.

## Gate

All six rows above matching FPC, plus the value rows in
`test/test_aggregate_function_results.pas` still green, self-host
byte-identical. Add the six rows as a test.

## Resolution (2026-08-10) — the silent half. One spelling stays refused.

**Root cause:** `ResolveNodeRec` (symtab.inc) dispatches an `AN_INDEX` on the
KIND of its base, and had an arm for every one of them — `AN_IDENT`, `AN_FIELD`,
a nested `AN_INDEX`, `AN_ADDR`, `AN_PTR_CAST` — **except a call**. So
`MkR[i]` fell to the `else` and answered `REC_NONE`, `FindUField` found nothing,
and the `.field` was built at offset 0. Every field of the element answered the
first one.

The fix is one arm, and it is a delegation rather than a sixth special case:
`ResolveNodeRec` already answers a bare call with `ProcRetRecId`, and for an
array-of-record result that IS the element record — so the index arm just
recurses into it, exactly like the nested-`AN_INDEX` arm above it.

`MkR[i].field` now matches FPC. Test: `test/test_index_call_result_field.pas`,
asserted in the Makefile.

### Still refused, deliberately, with a diagnostic that says so

Indexing an array-returning call whose element is NOT a record —
`MkArr[1]` for `function MkArr: array[0..2] of Integer`, and the dyn-array
result — has no addressable base: lowering answered `IR_UNSUPPORTED`, and
before that the stray `[` reached the statement parser as `unexpected token`
pointing at the wrong place. It now says:

    cannot index the result of an array-returning function directly —
    assign it to a variable first

The record-element spelling works only because it arrives through the
class/record selector arm (`Procs[].RetType` is the ELEMENT kind, so an array
of records reads as `tyRecord` there) — an accident of routing, not a designed
path.

**Making it work is one move, not five:** materialise the call result into a
hidden temp SHAPED like the array (`AllocArray` + the dim-span stamp) and index
the temp, via `AN_COMMA` — precisely what the AnsiString arm a few lines up
already does for `Uppercase(s)[2]`. That single change also brings the N-D
spelling `MkR2[i,j].field` with it (still a parse error today: the selector
walker's bracket arm reads ONE expression, and flattening a multi-index needs
dim spans a call node does not carry) and would let the record-element case stop
depending on the routing accident. It wants `ProcRetArrAi` — the result's
ArrType index, which nothing records yet — and it is a feature-shaped change
with a live question about dyn-array ownership, so it is filed separately rather
than half-wired here.

Follow-up: `feature-a-index-an-array-returning-call-directly`.

## Verified

- Both value rows against `fpc -O1` (`{$mode objfpc}`): via a variable (the
  control, always right) and directly on the call.
- N-D through a variable, `w[1,1].c`, also green — the N-D *call* row is left
  unasserted so nothing blesses either answer.
- `tools/gate.sh quick` GREEN, self-host fixedpoint converged in 1 round.
- Sweep vs `pinned` over `test/*.pas`: no behavioural difference beyond the
  known-environmental set (sockets, GTK timestamps, PIDs, harness `.so`s) and
  the two tests `pinned` cannot compile. C/NilPy sweep run separately.

## Log
- 2026-08-10 — resolved, commit PENDING-COMMIT.
