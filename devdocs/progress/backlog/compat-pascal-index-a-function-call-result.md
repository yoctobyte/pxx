---
summary: "Indexing a function call's result — `Copy(s,2,3)[1]`, `Make[0]`, `b.ArrP(3)[0]` — either fails to parse or reaches IR lowering as an un-lowerable AN_CALL; FPC accepts all three"
type: compat
track: P
prio: 40
---

# `f(...)[i]` — indexing a call result

- **Type:** compat (Pascal frontend parity) — Track P
- **Status:** backlog
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
