---
summary: "not ord(x) computes a BOOLEAN not (xor 1) instead of a bitwise complement — silently wrong integer"
type: bug
prio: 72
---

# `not ord(x)` does a boolean negation, not a bitwise complement

- **Type:** bug (silent wrong value). **Track P** (Pascal frontend — the type of an
  `ord()` result inside an expression).
- **Status:** backlog
- **Opened:** 2026-07-14
- **Found by:** Track T — `tools/pasmith.py`, first run of the widened grammar
  ([[feature-pasmith-widen-grammar]]), seeds 2 and 13 of an `--enums 2` run. **T owns
  the tool, never the bug** — filed here, not fixed there.

## Repro

```pascal
program en2;
{$mode objfpc}
{$Q-}{$R-}
type TE = (e0, e1, e2);
var e: TE; i: longint; c: char; b: boolean;
begin
  e := e1; i := 1; c := 'a'; b := true;
  writeln('not i          = ', longint(not i));         { plain int }
  writeln('not ord(e)     = ', longint(not ord(e)));    { enum }
  writeln('not ord(c)     = ', longint(not ord(c)));    { char }
  writeln('not ord(b)     = ', longint(not ord(b)));    { boolean }
  i := ord(e);
  writeln('via var        = ', longint(not i));         { same value, through a var }
end.
```

| expression | FPC 3.2.2 | pxx (HEAD) |
| --- | --- | --- |
| `not i` (i = 1) | `-2` | `-2` ✓ |
| `not ord(e)` (ord = 1) | `-2` | **`0`** |
| `not ord(c)` (ord = 97) | `158` | **`96`** |
| `not ord(b)` (ord = 1) | `254` | **`0`** |
| `i := ord(e); not i` | `-2` | `-2` ✓ |

## What pxx is actually doing

`97 xor 1 = 96`, `1 xor 1 = 0`. pxx is applying **boolean** `not` — flip bit 0 — to the
`ord()` result, where the operand is an integer and `not` must be a bitwise complement.
Assigning the same `ord()` to a variable first and negating *that* gives the right
answer, so the value is fine; it is the **static type of the `ord()` node inside the
expression** that is wrong. It looks as though `ord(x)` inherits its operand's kind
(enum/char/boolean) instead of becoming an integer, and `not` then picks its boolean
form off that type.

FPC's widths, for reference: `ord()` yields an integer of the operand's size, so
`not ord(c)` on a byte-sized char is `158` (byte complement) while `not ord(e)` on a
4-byte enum is `-2`. Both are bitwise; neither is a bit flip.

## Why it matters

It is silent. `not ord(...)` produces a plausible small integer, the program keeps
running, and every value derived from it is wrong. No diagnostic, no crash, and nothing
in the suite fails — the reason it survived until a fuzzer wrote the expression by
hand. Any code that hashes, masks or checksums an ordinal (`not ord(ch)` is an ordinary
thing to write in a hash) gets quietly wrong numbers.

The old pasmith grammar could not reach it: it only ever emitted `ord()` **inside a
cast** (`longint(ord(c))`), where `not` sees an explicit integer type and behaves. It
took a bare `ord()` leaf in an integer expression — which the enum rung introduced — to
write the shape at all.

## Where to look

Wherever a unary `not` chooses between its boolean and its bitwise form off the operand's
type, and wherever `ord()`'s result type is assigned. `ord()` must yield an *integer*
type (of the operand's size, to match FPC), not something still carrying the operand's
enum/char/boolean kind.

Worth checking the neighbours while in there: `-ord(x)` is correct today, but `succ`,
`pred`, and `not` of a *set* member expression sit on the same typing arm.

## Acceptance

- The table above matches FPC for all five rows under pxx.
- A `test/test_*.pas` regression covers `not ord(<enum>)`, `not ord(<char>)`,
  `not ord(<boolean>)` and the via-a-variable control case.
- pasmith's enum rung then drops its `longint(...)` wrapper around bare `ord()` reads
  (one line, marked `NO_BARE_NOT_ORD` in `tools/pasmith.py`) and the shape gets fuzzed
  properly.
