---
summary: "Indexing a call result: the FIXED-array, array-of-record and Copy-intrinsic spellings now match FPC; DYNAMIC-array results remain refused, and the fix needs one materialisation point rather than 20"
type: compat
track: P
prio: 40
owner: 
---

# `f(...)[i]` — indexing a call result

> **READ THIS FIRST (2026-08-19).** Scope is now **dynamic-array results only** —
> the fixed-array, array-of-record and `Copy(s,i,n)[k]` spellings all match FPC
> and are covered by `test/test_index_a_call_result_directly.pas`.
>
> **And this ticket's baseline below is WRONG.** It says *"`b.Arr[1]` — a
> paramless method returning a dynamic array — works and gives the right value.
> That is the shape to follow."* The PINNED compiler answers `IR_UNSUPPORTED
> (kind 8)` for it. Nothing gives that call a temp; the mechanism the ticket
> tells you to copy **does not exist**. The 2026-08-05 measurement was of a
> dyn-array class FIELD, not of a method result, and it has been steering this
> ticket ever since.
>
> The section at the bottom, *"what the dynamic half actually needs"*, is the
> current diagnosis — the hidden temp is not the hard part, `IRLowerAddress` is,
> and the fix is one materialisation point rather than twenty. Start there, not
> from the prose immediately below.

- **Type:** compat (Pascal frontend parity) — Track P
- **Status:** backlog (an earlier session left this line saying "working"; the folder is the lock and it was never held)
- **Opened:** 2026-08-05
- **Found by:** `tools/fpc_diff_probe.sh`, dynamic-array case batch
  (`dynarray-copy-and-alias`, now tagged `[known]`).

This is **two** gaps behind one syntax, and they fail differently.

## Gap 1 — parse error: an UNQUALIFIED call, indexed

```pascal
program dy3;
type TArr = array of Integer;
function Make: TArr;
begin SetLength(Result, 2); Result[0] := 7; Result[1] := 8; end;
var s: string;
begin
  s := 'hello';
  writeln(Copy(s, 2, 3)[1]);   { FPC: e }
  writeln(Make[1]);            { FPC: 8 }
end.
```

pxx on either line:

```
Expected: ), but got:  (Kind: 76, Line: 10)
pascal26:10: error: unexpected token
  near: s      >>>
```

The postfix `[` is not accepted after a call in an unqualified expression
position. (Note the diagnostic is also nearly contentless — `near: s >>>` with
nothing after the marker.)

## Gap 2 — parses, then cannot be lowered: a QUALIFIED call with arguments

```pascal
type
  TArr = array of Integer;
  TBag = class
    function Arr: TArr;
    function ArrP(k: Integer): TArr;
  end;
...
  writeln(b.Arr[1]);        { WORKS — prints 6 }
  writeln(b.ArrP(3)[0]);    { FPC: 3 }
  writeln(TBag.Create.Arr[0]);  { FPC: 5 }
```

```
pascal26:14: error: IR_UNSUPPORTED: frontend could not lower AST node (kind 8)
  — a frontend gap, would miscompile
```

Kind 8 is `AN_CALL` (`compiler/defs.inc:198`). So the parser builds the index
over a call node and the lowering has no path for it — it needs a temporary to
hold the returned dynamic array before indexing, the same temp the paramless
case already gets.

**`b.Arr[1]` — a paramless method returning a dynamic array — works and gives
the right value.** That is the shape to follow: whatever gives the paramless
qualified call its temp is what the other three need.

## Why it matters

`SplitString(s, ',')[0]`, `Copy(line, 1, 4)[1]`, `GetItems(k)[0]` are ordinary
Pascal. The failure mode is at least honest — a parse error or a loud
IR_UNSUPPORTED, never a wrong value — so this is a gap, not a corruption.

## Gate

Track P: `make test` + self-host fixedpoint (byte-identical). Track P catch —
the Pascal frontend lives in the shared `lexer.inc`/`parser.inc`, so this must
not be edited concurrently with Track A. The `[known]` probe case starts
reporting the moment it works.


## NARROWED 2026-08-05 — one of the two gaps is already closed; the rest is smaller than described

Measured at HEAD. The syntax does **not** fail uniformly:

| form | result |
| --- | --- |
| `Nm()[1]` — explicit call, **string** result, indexed | **works** |
| `MakeR.a` / `MakeR().a` — call result, **.field** postfix | **works** |
| `Make[1]` — bare paramless call, **dyn-array** result | parse error |
| `MakeN(1)[1]` — explicit call, **dyn-array** result | parse error |
| `Copy(s,2,3)[1]` — **builtin intrinsic**, string result | parse error |
| `a := Make; a[1]` (control) | works |

So the ticket's "either fails to parse or reaches IR lowering as an un-lowerable
AN_CALL" is now only half true:

- **The LOWERING half is done.** `IRLowerAddress` accepted a call in address
  position only for `tyRecord`/`tyVariant`; it now also accepts `tyAnsiString`
  and the frozen kinds
  (`bug-p-index-getter-backed-string-property`, fixed today). That is why
  `Nm()[1]` works, and it means a string-returning call no longer reaches
  lowering un-indexable.
- **What remains is purely PARSE-side, and is two narrower cases**, not one
  broad one:
  1. a **dynamic-array**-returning call, indexed — fails with parens or without,
     so it is the RESULT TYPE that matters, not the call spelling;
  2. a **builtin intrinsic** (`Copy`) whose branch `Exit`s before any postfix
     chain runs — a different code path from a user call, which is why
     `Nm()[1]` and `Copy(...)[1]` disagree despite both returning a string.

Recording rather than fixing: the hook is inside the Pascal factor parser's
call branch, which is the densest function in the file with many early `Exit`s,
and a mis-placed postfix loop there changes expression parsing everywhere. It
wants a session with room to gate properly, not a tail-end patch. The two cases
above are the actual scope, and the lowering they need already exists.

## 2026-08-09 — one more row, and it narrows Gap 1

A **string**-returning call indexed directly already works; only the array kinds
fail to parse. Measured at `9f01b58e3`:

```pascal
function MkStr: AnsiString; begin MkStr := 'abc'; end;
function MkDyn: TIntArr;    begin SetLength(MkDyn, 3); MkDyn[1] := 8; end;
function MkFix: TArr3;      begin MkFix[1] := 2; end;

WriteLn(MkStr[2]);   { FPC b   pxx b   — works }
WriteLn(MkDyn[1]);   { FPC 8   pxx: unexpected token }
WriteLn(MkFix[1]);   { FPC 2   pxx: unexpected token }
```

So the suffix machinery is reachable from a call result already — `PySubscriptableSuffix`
/ the `[` loop in ParseFactor accept a call whose static type is a string — and
what is missing is the ARRAY arm of the same test, not the whole path. That
should make Gap 1 considerably smaller than the ticket assumed.

`MkFix` (a FIXED array result) additionally needs
[[bug-a-set-and-array-function-results-come-back-empty]]'s hidden-destination
work, which landed 2026-08-09 — before that, an indexed fixed-array call result
would have read a register holding element 0.

Found while running a dynamic-array/pointer FPC differential for Track A; the
rest of that surface (SetLength, Copy detaching, alias semantics, 2-D dyn,
records, New/Dispose, nil, empty) matches FPC exactly.

## 2026-08-19 — the FIXED-array and INTRINSIC halves are done; the DYNAMIC half is not, and the ticket's own baseline was wrong

Landed under [[feature-a-index-an-array-returning-call-directly]] plus the Copy
fix below. Covered by `test/test_index_a_call_result_directly.pas`, whose
`.expected` is FPC's output for that same file, wired into `test-core`.

| form | before | now |
| --- | --- | --- |
| `MkS[2]` — string result | works | works |
| `MkArr[1]`, `MkArr2[i,j]`, `MkArr2[i][j]` — FIXED array | parse error | **= FPC** |
| `MkStr[1]` — `array[0..2] of string[8]` | parse error | **= FPC** |
| `MkR[1].a`, `MkR2[i,j].a`, `MkR2[i][j].a` — array of record | 1-D only | **= FPC** |
| `Copy(s, 2, 3)[1]` — BUILTIN intrinsic | parse error | **= FPC** |
| `Make[1]` — dynamic result | parse error | refused, clear message |
| `b.ArrP(3)[0]`, `b.Arr[1]`, `TBag.Create.Arr[0]` — qualified, dyn | see below | unchanged |

**Gap 2 was a routing bug, not an intrinsic-specific one.** `Copy`'s branch in
`ParseFactorCore` builds an ordinary `AN_CALL` (onto `__pxxStrCopy`) and then
`Exit`s, straight past the postfix chain — so the trailing `[` reached the
statement parser as a stray token. It now calls `ApplyCallResultPtrSuffix` like
every user call does. That is the whole of the intrinsic half: one shared walk,
no second path.

### Correction to this ticket's own baseline

> **`b.Arr[1]` — a paramless method returning a dynamic array — works and gives
> the right value.** That is the shape to follow.

**It does not, and it did not.** The PINNED compiler — which predates all of
this work — answers `IR_UNSUPPORTED ... (kind 8)` for both `b.Arr[1]` and
`TBag.Create.Arr[0]`. The 2026-08-05 measurement was of a `TArr = array of
Integer` *class field*, not of the method result, and it has been steering the
ticket ever since: "whatever gives the paramless qualified call its temp is what
the other three need" describes a mechanism that does not exist. Nothing gives
it a temp. (`frank2-a-scan-in-a-ticket-reads-as-current`.)

### What the dynamic half actually needs — measured, not assumed

The hidden temp is **not** the hard part, which is what this ticket and the
Track A one both assumed. A dyn-array temp allocated with `AllocDynArray` in the
enclosing routine's scope gets the ordinary dyn-array release: 200 000
iterations of `acc := acc + Make[1]` hold RSS flat at 264 kB, and the sum is
right. The lifetime story already exists.

The hard part is the other end. `IRLowerAddress` must answer the address of a
SLOT HOLDING the handle; a dyn-array call's IR value **is** the handle. Adding
dyn-array calls to that procedure's aggregate arm (`ir.inc` ~1733, next to the
managed-string case whose rationale reads as if it covers this) makes the index
path read the handle as though it were the slot:

```
TBag.Create.Arr[0]   FPC 5   pxx 25769803781 = 0x600000005
```

— elements 0 and 1 as one 8-byte word. **A silent wrong value where there had
been a loud refusal**, which is strictly worse, so it was reverted rather than
landed. Materialising the temp inside `IRLowerAddress` instead fixes both
spellings and leaks one array per call, because that temp has no owner and no
scope: a silent leak for a silent wrong value is not a trade.

The shape that works is **routing every call-result suffix through
`ApplyCallResultPtrSuffix`**, so there is one materialisation point with one
lifetime story. Today the ~20 `mcallNode` sites in `ParseFactorCore` each index
a call node on their own, which is exactly why the unqualified spelling could be
fixed in one arm and the qualified ones could not. That is a real refactor and
its own sitting; the diagnosis above is what it needs to start, and the refusal
in the meantime is loud.

**Remaining scope: dynamic-array results only, qualified and unqualified.**
