---
track: P
prio: 50
type: bug
blocked-by: []
summary: "`for d in [1.5, 2.5, 3.5] do` iterates ONCE and binds 0.0 — the element count and every value are lost. The same loop over an INTEGER or STRING constructor is correct, and over a dynamic array of Double is correct, so it is specifically a float ARRAY CONSTRUCTOR as the for-in source. FPC iterates all three elements"
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
