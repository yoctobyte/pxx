---
track: A
prio: 40
type: bug
blocked-by: []
status: done
owner: claude-A
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

## Resolution (2026-08-11) — and a THIRD fault the ticket did not know about

Both recorded faults are fixed, and measuring the Text-file half first turned up
a silent one that was worse than either:

**`write(f, s:5)` to a Text file dropped the width — with a LITERAL width too.**
`TextStrArg` handed a string straight through because a string needs no
conversion; it still needs PADDING. FPC writes `[   ab]`, pxx wrote `[ab]`, no
diagnostic, on every target. A Boolean was worse than dropped: it fell into the
ordinal arm and printed `1`/`0` where FPC prints `TRUE`/`FALSE`.

1. **The guard was too narrow.** The stdout variable-width branch now accepts
   any ordinal, string or float — the same set the literal path formats inline —
   instead of "float or (ordinal and not char/boolean)". Two paths disagreeing
   about what is writable, the recurring shape.
2. **The formatters now exist and are reachable.** `StrStrW` (pad a string) and
   `StrBool` (FPC's TRUE/FALSE, padded) join `StrInt`/`StrFloat`/`StrChar` in
   `compiler/builtin/builtin.pas`, and the token pre-scan pulls the builtin unit
   when a `write`'s `:` is followed by something other than an integer literal.
   So a program with **no `uses` clause** now compiles `writeln(i:w)` instead of
   failing with "write(Text): StrInt not loaded" — a message that named a Text
   file the program never opened and a routine the user never wrote. A LITERAL
   width still formats inline and pulls nothing.

Verified against `fpc -O1`: string / Char / Boolean / Integer / Double with a
variable width in a bare program, matching on x86-64 and all four cross targets;
and the whole Text-file matrix (literal and variable width, all five types)
byte-identical to FPC's output file. `test/test_write_char_field_width.pas`
extended with the variable-width rows, in a program that deliberately has no
`uses` clause.

**Needs a pin before other lanes see it:** the two new formatters live in
`compiler/builtin`, so Track B/E builds (which use `$(PXX_STABLE)`) keep the old
behaviour until `make stabilize-fast && make pin`. Not pinned here — nothing is
blocked on it today, and a pin would also bless the same session's shift-width
change, which is out for re-confirmation
(`decide-shift-native-width-costs-more-fpc-parity-than-the-table-showed`).

## Log
- 2026-08-11 — resolved, commit PENDING-COMMIT.
