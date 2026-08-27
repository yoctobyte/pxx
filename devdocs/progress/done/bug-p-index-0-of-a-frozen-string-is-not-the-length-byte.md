---
summary: "`s[0]` on a shortstring reads 0 instead of the length and `s[0] := #1` writes $0100000000000002 into it — index 0 lands on the TOP byte of the 8-byte length word"
type: bug
track: P
prio: 50
status: done
---

# Index 0 of a frozen string is not the length byte

- **Type:** bug (IR lowering / frozen strings) — Track P
- **Opened:** 2026-08-27
- **Found by:** the FPC-compiler corpus march. `cutils.pas:1429` is
  `inc(minilzw_encode[0])`. Recorded as adjacent case (2) on
  `bug-p-a-shortstring-function-result-prints-as-a-pointer` and confirmed
  pre-existing on the pinned compiler.

`s[0]` is the classic shortstring length byte, and FPC's own compiler sources
build strings with it. pxx got both directions silently wrong:

```pascal
var s: shortstring;
s := 'ab';
writeln(ord(s[0]));              { FPC 2                pxx 0                  }
s[0] := #1;
writeln(s, '|', length(s));      { FPC a|1              pxx |72057594037927938 }
```

## Root cause

`IR_INDEX` addresses `base + (i - lo) * elemSize`, and a frozen string uses
`lo := -7` (`ir.inc:1867`) so that index 1 lands on `data[0]` at `base+8`. Index
0 therefore landed on `base+7` — the **top** byte of the 8-byte length word.
Reading it gives 0 for any length under 2^56; writing `#1` there produced
`$0100000000000002`, exactly the value measured.

## Fix

`compiler/ir.inc`, the frozen-string arm of the index lowering: give index 0 its
own origin, `lo := 0`.

The length's **low** byte is at `base+0` on little-endian, and a frozen string's
capacity is ≤ 255, so one byte there *is* the length. Reads return it; writes
leave the upper seven bytes at the zero a full 8-byte length store already put
there. No separate load/store path, no new node kind, no branch on the hot
`s[i]` path — one origin constant.

**Compile-time constant 0 only.** A runtime index of 0 would need a branch per
access to choose between two origins, and FPC's idiom is always the literal.
Flagged below rather than paid for on every character access.

## Outcome — FIXED, 2026-08-27

`test/test_frozen_string_length_byte.pas` (wired into `test-core`) is
**byte-identical to the FPC 3.2.2 oracle** across eleven rows: reading the
length, growing through `inc(s[0])` and appending, truncating with `s[0] := #1`,
emptying with `#0`, rebuilding one character at a time through a `var
shortstring` parameter, the sized `string[N]` spelling, a frozen string in a
**record field** in both directions, and a runtime-indexed loop kept as a guard
that ordinary character access is untouched.

`gate.sh quick` GREEN; Pascal conformance 346/0/170/34, C conformance 220/0,
fgl 7/7.

## Flagged, not built

1. **A runtime index of 0** still reads `base+7`. Needs a per-access branch;
   deliberately not paid for. FPC's own sources never write it.
2. **`funcname[i]` — indexing the result through the FUNCTION'S OWN NAME — does
   not parse** (`undefined variable (Build)`, then `Expected: ), but got: [`).
   `Result[i]` works, and is what this repo's tests use. This is the last thing
   between here and `cutils.pas:1429`, which spells it
   `inc(minilzw_encode[0])`; it belongs with the other call-result postfix gaps
   (`Copy(...)[i]`, the record cast, `P[1]`), all of which are the same missing
   `[` on a walker rather than anything about strings.

## Log
- 2026-08-27 — resolved, commit fed3e1f43.
