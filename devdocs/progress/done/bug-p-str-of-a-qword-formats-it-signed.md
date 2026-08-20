---
track: P
prio: 60
type: bug
blocked-by: []
summary: "`Str(q, s)` on a QWord >= 2^63 produced '-1' — the intrinsic had no unsigned dispatch at all, while `writeln(q)` two lines away was right. write(Text) had the dispatch but keyed it on `tk = tyUInt64`, one of four spellings of an 8-byte unsigned, so `writeln(f, pu)` with `pu: PtrUInt` printed -1 too."
status: done
owner: frank1-ACP
---

# `Str` of a QWord formats it signed

- **Track P** (the `Str` intrinsic and the `write(Text)` formatter chooser, both
  in `parser.inc`).
- Found 2026-08-20 by an FPC differential probe over unsigned edge values,
  written while chasing the mixed-signedness comparison bug.

## Repro

```pascal
var q: QWord; s: string;
begin
  q := 18446744073709551615;
  writeln(q);          { 18446744073709551615 — right }
  Str(q, s);
  writeln('[', s, ']');{ [-1] — same value, same program, four lines apart }
end.
```

## Cause

Three code paths format an ordinal, and each spelled "is this unsigned?"
differently:

| path | predicate | verdict |
| --- | --- | --- |
| stdout `write` (codegen) | `not TypeSigned(tk)` | right |
| `write(Text)` (parser) | `tk = tyUInt64` | misses tyNativeUInt |
| `Str(x, s)` (parser) | *nothing* | always signed |

`tyUInt64` and `tyNativeUInt` are two of the four *source* spellings of an
8-byte unsigned (QWord, UInt64, NativeUInt, PtrUInt), so the middle row printed
`-1` for `pu: PtrUInt` while getting `q: QWord` right — the narrower kind of
double case, where even the path that HAD the dispatch had only half of it.

## Fix

All three use the stdout path's predicate. `Str` picks `StrQWord` for any
unsigned ordinal (Char and Boolean keep their own formatters), `write(Text)`
drops the `= tyUInt64` test for `not TypeSigned`. A narrower unsigned is
zero-extended and formats identically either way, so there is nothing a width
test would add.

## Neighbour, deliberately not touched

`High(QWord)` / `Low(UInt64)` / `High(NativeUInt)` / `High(PtrUInt)` are still
REJECTED at compile time ("undefined variable"), the documented refusal from
`bug-p-high-low-reject-the-64-bit-type-aliases`: the const evaluator carries
`Int64`, and answering -1 would turn a refusal into a wrong value. Refiled as
`feature-p-const-evaluator-carries-unsigned-64-bit` so the representation change
is tracked rather than rediscovered.

## Gate

`test/test_str_of_unsigned.pas` — 23 assertions, all `fpc -O- -Mobjfpc` 3.2.2's:
the four 8-byte unsigned spellings, 2^63 exactly, narrower unsigned, all five
signed types, widths on both sides of the dispatch, expressions rather than
variables, and the same values through a Text file. The pinned binary scores
17/23. Wired into `make test`; `tools/gate.sh quick` GREEN, self-host fixedpoint
byte-identical.
