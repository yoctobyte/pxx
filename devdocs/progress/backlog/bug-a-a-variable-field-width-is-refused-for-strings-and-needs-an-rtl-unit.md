---
track: A
prio: 40
type: bug
blocked-by: []
---

# A VARIABLE field width is refused for strings/chars, and needs an RTL unit at all

- **Type:** bug (wrong refusal + a diagnostic that names the wrong thing) — **Track A**
- **Found:** 2026-08-10 alongside
  [[bug-a-x86-64-write-ignores-a-field-width-on-a-char]] (the Char *literal*
  width, now fixed). This is the non-literal-width half.
- **Pre-existing.**

FPC accepts `write(v:w)` for any writable `v` and any integer expression `w`.
Measured against `fpc -O1`:

| value | literal width `v:5` | VARIABLE width `v:w` |
| --- | --- | --- |
| Integer / float | ok | ok — **but only if an RTL unit is used** (below) |
| String (2+ chars) | ok | **refused**: `write: variable width needs an integer or float value` |
| Char (incl. a 1-char literal) | ok (fixed) | **refused**, same message |
| Boolean | ok | **refused**, same message |

FPC prints `[   ab]` / `[    q]` for the refused rows.

## Two separate faults

1. **The guard is too narrow.** `ParseTextWriteRest`'s variable-width branch
   tests `float or (ordinal and not char/boolean)` and errors otherwise. Strings,
   Chars and Booleans have perfectly good formatters; they are simply not
   routed. The literal path already handles all four types, so the two paths
   disagree about what is writable — the recurring shape.

2. **The variable-width path needs `StrInt`/`StrFloat`, which a bare program
   does not have.** `TextStrArg` pre-formats through those RTL routines, so
   in a program with no `uses` clause, `writeln(i:w)` fails with

       write(Text): StrInt not loaded

   which names `Text` in a program that never mentioned a text file, and names
   a routine the user never wrote. `uses SysUtils` makes it work. Either the
   formatters must be reachable the way the literal path's inline emitters are,
   or the message must say what to add.

## Where

`compiler/parser.inc`, `ParseTextWriteRest` (the `variable width/decimals` else
branch) and `TextStrArg` just above it.

## Gate

The four value types above with a variable width matching FPC, in a program with
**no** `uses` clause, on x86-64 plus the cross targets; self-host
byte-identical. Extend `test/test_write_char_field_width.pas` with the
variable-width rows it currently omits.
