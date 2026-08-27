---
summary: "`writeln(P)` where `P: shortstring` prints the struct POINTER (4304016) instead of `ab` — a call carries its result's STORAGE kind, so the write dispatch's `= tyString` test misses it"
type: bug
track: P
prio: 50
status: done
---

# A shortstring function result prints as a pointer

- **Type:** bug (codegen / write dispatch) — Track P
- **Opened:** 2026-08-27
- **Found by:** the FPC-compiler corpus march. `cutils.pas:1429` writes
  `inc(minilzw_encode[0])` — the classic shortstring length byte on a result —
  which led to measuring what a frozen-string result does at all.

Silently wrong OUTPUT, no diagnostic, on the plainest possible program:

```pascal
function P: shortstring;
begin P := 'ab'; end;
begin
  writeln('a ', P);      { FPC: `a ab`   pxx: `a 4304016` }
end.
```

`writeln(s)` on a shortstring **variable** was always fine. Only the **result**
of a function was wrong, which is exactly the shape that hides: the value is
right everywhere it is stored (`t := P` gives `ab`), right in `Length`, right
in a comparison — and wrong only when printed.

## Root cause

`StrValTk` (`symtab.inc:3129`) is the designed normalisation: a symbol whose
*storage* kind is `tyShortString` / `tyFixedString` presents as a `tyString`
**value**, "so every existing `= tyString` value check (write, concat, compare,
…) keeps working without widening ~150 sites". Every symbol-read site calls it.

A **call** node does not. It takes `Ord(Procs[pi].RetType)` verbatim — the
storage kind — at some 50 sites across `pasparser_call.inc`,
`pasparser_lval.inc` and `pasparser_expr.inc`. So `tyShortString` reached the
`IR_WRITE` dispatch, whose string-valued arm tested `= tyString`, missed, and
fell through to the **integer** arm, which printed the struct address.

Fixing this at the ~50 producers would be the wrong end. `TypeIsFrozenString`
exists precisely for the other end, and says so in its own note: *"Widen
existing `= tyString` codegen checks to this predicate so the new kinds route
through the frozen-string path without 250 new arms."* One consumer, one
predicate.

## Fix

`compiler/ir_codegen.inc`, the `IR_WRITE` dispatch:

1. `IntToTypeKind(IRTk[node]) = tyString` → `TypeIsFrozenString(...)`, so a
   frozen-string **value** reaches the string arm.
2. That arm never learned **field width**. Every other arm had — the
   symbol-read `tyString` path, the `tyAnsiString` path, even the Char path —
   so `writeln(s:5)` padded for a shortstring VARIABLE and not for a value.
   Latent before (a genuine `tyString`-valued expression is rare); reachable
   the moment (1) landed. Padding added, same shape as the `tyAnsiString` arm.

## Outcome — FIXED, 2026-08-27

`test/test_shortstring_function_result.pas` (wired into `test-core`) is
**byte-identical to the FPC 3.2.2 oracle** across nine rows: a `shortstring`
result, a `string[N]` result, a result with an argument, a result mutated
through `Result[1]`, a **method** result (a different parser path to the same
dispatch), and the paths that already worked kept as guards — assignment out of
the result, `Length` of it, `=` against a literal, and the field width.

`gate.sh quick` GREEN; Pascal conformance 346/0/170/34, C conformance 220/0,
fgl 7/7.

## Adjacent, measured and deliberately NOT built

Both were verified **pre-existing on the pinned compiler**, i.e. neither is a
regression from this fix:

1. **A frozen-string result as a CONCAT operand is still wrong.**
   `writeln(P + '!')` prints a pointer, and `a := P + '!'` gives the empty
   string, while the same concat on a shortstring VARIABLE is correct
   (`v + '!'` → `ab!`). Same root cause — the call node's tk — but a different
   consumer, and the `+` typing lives across a dozen `= Ord(tyString)` operand
   tests in `pasparser_expr.inc`. Widening those is a real sweep with its own
   gating, not a rider on this one.

2. **`s[0]` is not the shortstring length byte.** FPC's classic idiom reads and
   writes the length through index 0:

   ```pascal
   var s: shortstring;
   s := 'ab';
   writeln(ord(s[0]));   { FPC 2      pxx 0     }
   s[0] := #1;
   writeln(s, '|', length(s));
   { FPC `a|1`   pxx `|72057594037927938` }
   ```

   pxx indexes `s[i]` as `data + (i-1)`, so `s[0]` lands on the last byte of the
   8-byte length prefix: reading gives the top byte (0), and writing `#1` there
   produced `$0100000000000002`, exactly as measured. The length is 8 bytes wide
   whatever `FrozenStrSlotSize` says about `cap + 1`, which is itself worth a
   look. The fix is to make index 0 *mean the length* rather than be pointer
   arithmetic — a normalisation, not a special case — but it touches every
   frozen-string index site (read, write, `inc`) and belongs in its own ticket.
   `cutils.pas:1429` needs this **and** (1) before it compiles.

3. **`P[1]` — indexing a frozen-string result — does not parse**
   (`Expected: ), but got: [`). Same family as the `Copy(...)[i]` and
   record-cast indexing already fixed this week: a postfix `[` the call-result
   walker does not carry. Not needed by the corpus march yet.

## Log
- 2026-08-27 — resolved, commit 8a62d7eb4.
