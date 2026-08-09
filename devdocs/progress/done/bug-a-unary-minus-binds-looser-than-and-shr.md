---
track: A
prio: 60
type: bug
blocked-by: []
status: done
---

# Unary minus binds looser than `and`/`shr` — `-x and 12` was `-(x and 12)`

- **Type:** bug (silent wrong value, Pascal AND C) — **Track A** (shared
  expression grammar in `parser.inc`)
- **Found:** 2026-08-09, an FPC differential over the ordinal/shift surface.
- **Pre-existing.**

```pascal
var x: Integer;  x := 8;
-x and 12     { FPC 8                    pxx -8 }
-x shr 1      { FPC 9223372036854775804  pxx -4 }
```

and in C, against gcc:

```c
int x = 8;
-x & 12       /* gcc 8    pxx -8 */
```

## Cause, and why it survived

`ParseSimpleExpr` ate the unary minus at the ADDITIVE level for Pascal and C,
leaving Python to negate at the factor level. The comment justified it:

> Unary minus is an ADDITIVE-level sign in Pascal — `-7 div 2` really is
> `-(7 div 2)` in FPC

That is true and **unobservable**: `-(7 div 2)` and `(-7) div 2` are both -3.
The same holds for `*`, `+`, `mod` and `shl`. The operators that expose the
difference are **`and` and `shr`**, and the note picked `div` — the one operator
that cannot answer the question it was asked. So the file
`test/test_const_precedence.pas` has asserted "unary minus binds tightest" since
it was written, while testing only cases that hold either way.

## Fix

The minus always falls through to `ParseFactor`'s own `tkMinus` case, which
negates ONE factor — the path PyExprMode already used, for the same reason. One
line, plus the note rewritten to say what was measured.

## Blast radius, checked rather than assumed

`grep` for `-<name> and` / `-<name> shr` across `compiler/**` and `lib/rtl/**`
finds only prose inside comments — no source of ours uses a shape whose meaning
changes, which is consistent with the self-host converging.

## Verified

- `test/test_const_precedence.pas` extended with the rows that actually pin the
  binding (`and` as a constant and through a variable), since every existing row
  passes either way. FPC and pxx now print the same 15 lines.
- The C differential above matches gcc on all six rows, including `-x & 12`
  which was wrong before.
- Left open and NOT asserted: `-x shr 1` on a 32-bit operand still shifts at 32
  bits where FPC promotes to 64 — a width question with its own ticket,
  [[bug-a-shr-on-a-32-bit-operand-does-not-promote-like-fpc]].

`make compiler/pascal26` fixedpoint + `tools/gate.sh quick` + `make test-core`
GREEN.

## Log
- 2026-08-09 — resolved, commit PENDING-COMMIT.
