---
track: C
prio: 40
type: bug
status: done
found: 2026-08-30
found-by: frankC
summary: "`(double)(a+b)` for two floats prints 0.300000004 where gcc prints 0.300000012 — the addition is done at DOUBLE width and rounded once, instead of at float width. All five targets. The narrowing machinery exists; the binary operator is the arm that does not use it."
---

# `float + float` is computed at double width

C 6.3.1.8: the usual arithmetic conversions on two `float` operands give
`float`, and the result is a float. We compute in double and round once at the
end, which is a different answer whenever the two roundings differ.

## Measured, x86-64, against gcc

```c
float a = 0.1f, b = 0.2f;
printf("%.9f\n", (double)(a+b));   /* gcc 0.300000012   pxx 0.300000004 */
```

`0.300000012` is the single sum; `0.300000004` is the double sum widened. Both
are "0.3" to a careless eye, which is why this survives — it is a **wrong value
that looks right**, and a comparison against a float computed the other way
branches differently.

Not a formatting question and not Track F: the mechanism is *which width an
operator evaluates at*, which is a type rule, not float math. Rank the
mechanism, never the datatype.

## What is already right, which is the whole shape of the fix

- `float f3(void) { return 1.0f/3.0f; }` → `0.333333343`, matching gcc. The
  **return type** forces the narrowing.
- A store into a float lvalue narrows.
- `(float)x` narrows, through the anonymous tySingle temp round-trip.
- `sizeof(1.0f+1.0f)` is now 4 — so the binop's static TYPE is already single;
  only its evaluation width is wrong.

That last line is the useful one: the node knows it is a float. The narrowing
machinery exists and is proven on all five backends. This is the fourth arm of
the same double case — after the `(float)` cast, the `(double)` mirror, and the
`f` suffix — and, as with those, the fix is likely to route it through the
existing round-trip rather than add a path.
[[bug-c-the-f-suffix-on-a-float-literal-is-ignored]]

## Found by

Building the canary for the `f`-suffix fix. It is a **pre-existing** defect and
not a regression from that work: the pinned binary predating it prints
`0.300000004` too. Recorded here because measuring the baseline is what
separated the two, and a reader of the f-suffix ticket will otherwise wonder why
this row is not in its test — it is out of scope there on purpose, so that one
red does not stand for two mechanisms.

## Log
- 2026-08-30 — resolved, commit 60ab63fc9.
