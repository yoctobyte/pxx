---
track: P
prio: 50
type: bug
blocked-by: []
summary: "`for d in [1.5, 2.5, 3.5] do` iterates ONCE and binds 0.0 — the element count and every value are lost. The same loop over an INTEGER or STRING constructor is correct, and over a dynamic array of Double is correct, so it is specifically a float ARRAY CONSTRUCTOR as the for-in source. FPC iterates all three elements"
status: done
owner: agent-an-night
---

# `for … in [1.5, 2.5]` iterates once, with 0.0

- **Type:** bug (silent wrong value + lost iterations) — **Track P** (Pascal
  frontend; the for-in desugar lives in the shared `parser.inc`, so it lands
  under Track A's gate)
- **Found:** 2026-08-12, differential bug hunting against FPC 3.2.2.

```pascal
var d: Double;
begin
  for d in [1.5, 2.5, 3.5] do WriteLn(d:0:2);
end.
```

| | |
| --- | --- |
| FPC | `1.50` / `2.50` / `3.50` |
| pxx | `0.00` — one iteration, and the value is zero |

Counting the iterations confirms the loop body runs exactly once:

```pascal
n := 0;
for d in [1.5, 2.5] do Inc(n);
WriteLn(n);      { FPC: 2   pxx: 1 }
```

## The boundary — it is the FLOAT constructor specifically

| source | pxx |
| --- | --- |
| `for d in [1.5, 2.5, 3.5]` (Double) | **once, 0.0** |
| `for i in [10, 20]` (Integer) | correct |
| `for s in ['a', 'b']` (String) | correct |
| `for d in a` where `a: array of Double` | correct — `1.50`, `2.50` |

So the for-in machinery, the loop variable and the Double element type are all
fine; it is the ARRAY CONSTRUCTOR with float elements that produces neither the
right count nor the right values. A one-element constructor (`[1.5]`) is wrong
too, which rules out a stride/length miscount alone — the element is not being
read as a Double at all.

Reads like the constructor being built with an integer element width (a zero
value and a count divided by the wrong stride is what an 8-vs-? mismatch
produces), i.e. the same shape as the frozen-string/element-width family:
the element type is not carried to the site that lays the constructor out.
`PXXDBG=a.ast` on the loop statement and the emitted IR for the constructor
should say which.

## Gate

A `.pas` diffed against FPC: one-, two- and three-element float constructors,
mixed `[1, 2.5]` (FPC promotes), the integer/string/dynamic-array controls in
the same file, a constructor built from float CONSTANTS and from variables, and
an iteration count asserted alongside the values.

## Fixed 2026-08-15 — the rule is chosen by the LOOP VARIABLE, not the elements

The ticket's boundary table was right and its guessed cause ("built with an
integer element width") was not. `for x in [ ... ]` was implemented as a SET
constructor unconditionally, with the element kind sniffed from the first
element (tyChar, else tyInteger). A float list therefore became a *set built
out of float bits*: one iteration, value 0.0.

Measuring FPC 3.2.2 gives the actual rule, and it is not about the elements at
all — **FPC decides from the type of the variable being iterated into**:

| loop variable | `['b', 'a']` yields | `[5, 1]` yields |
| --- | --- | --- |
| `Char` | `a b` (SET, ordinal order) | — |
| `Integer` / `Byte` | — | `1 5` (SET, ordinal order) |
| `AnsiString` | `b a` (ARRAY, source order) | — |
| `Double` | — | source order |

One literal, two readings. That is the fact the old code could not represent,
because it never looked at the loop variable.

So: ordinal loop variable keeps the set path unchanged; anything else parses
the brackets with `ParseArrayCtorAST`, drops the result into a dyn-array temp
(`AllocDynArray`) and runs the ordinary iterable-variable loop over it — the
same shape the string-LITERAL arm already used, so length and element load come
from one lowering rather than a new one. `tyAuto` is pxx's own extension with
no FPC answer to copy: it infers from the first element token and keeps today's
set reading for everything that is not plainly a float or a multi-character
string.

Two things worth knowing, found only because FPC was run rather than assumed:

- **`[1, 2.5]`: FPC prints `1.00 0.00`** — it drops the 2.5. The ticket
  predicted "FPC promotes"; it does not. pxx answers `1.00 2.50` and does not
  copy the data loss, which is a deliberate divergence recorded at the row in
  the test and escalated as [[decide-forin-mixed-int-float-ctor-vs-fpc]].
- **`['abc', 'de', 'f']`: FPC prints `f?`** for the single-character element —
  it types it as a Char in that position. Unrelated quirk; the test uses
  multi-character elements throughout so the oracle stays clean.

### Verified

`test/test_forin_nonordinal_array_ctor.pas` + `.expected` in `test-core`,
covering all of the Gate section: one-, two- and three-element float
constructors, a reversed one (so source order is actually asserted), an
iteration COUNT, a constructor built from VARIABLES, a string constructor, the
`['b','a']` pair that proves the rule both ways, and the integer / dynamic-
array-of-Double controls in the same file. **Byte-identical to FPC 3.2.2 on
every row except the documented `[1, 2.5]` one.** The existing
`test_forin_literal_sources.pas` (the set half) still passes unchanged.

`gate.sh quick` + self-host fixedpoint GREEN, FPC seed canary included.

## Log
- 2026-08-15 — resolved, commit 27deacd86.
