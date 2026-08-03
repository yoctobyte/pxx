---
track: C
prio: 85
type: bug
summary: "Any CAST inside a static array/struct initializer folds to 0, for every type — `int b[2] = {(int)0xFF, 0}` gives 0 where gcc gives 255. Arithmetic in the same position folds correctly, so only the cast form is affected. Silent wrong data in every static table that casts."
---

# A cast in a static aggregate initializer folds to 0

- **Type:** bug (C frontend, silent wrong value) — **Track C** (cfront,
  static-initializer constant folding)
- **Found:** 2026-08-03 by claude-C@opus5 while fixing
  [[bug-cfront-plain-char-is-unsigned-and-folds-inconsistently]]. **Pre-existing
  and independent** — reproduced identically on
  `stable_linux_amd64/default/pinned`, which predates that change.
- **Severity:** silent wrong DATA, not a diagnostic. Filed to `urgent/`.

## Measured

```c
#include <stdio.h>
int   b1[2] = { (int)0xFF, 0 };
char  c1[2] = { (char)1, 0 };
char  c2[2] = { (char)0x7F, 0 };
char  c3[2] = { (unsigned char)0xFF, 0 };
short s1[2] = { (short)0xFF, 0 };
char  c4[2] = { 1 + 1, 0 };          /* arithmetic, not a cast */
int main(void) {
  printf("b1=%d c1=%d c2=%d c3=%d s1=%d c4=%d\n",
         b1[0], (int)c1[0], (int)c2[0], (int)c3[0], (int)s1[0], (int)c4[0]);
}
```

| | `b1` | `c1` | `c2` | `c3` | `s1` | `c4` |
| --- | --- | --- | --- | --- | --- | --- |
| **gcc** | 255 | 1 | 127 | -1 | 255 | 2 |
| **pxx** (and `pinned`) | **0** | **0** | **0** | **0** | **0** | 2 |

Every cast folds to 0, whatever the type and whatever the value — even
`(char)1`, where no truncation or signedness question arises. `1 + 1` in the
same position is correct, so the static-initializer folder handles ordinary
constant expressions and specifically loses the cast.

## Scope — where it bites

Only the **static** (file-scope / `static`) aggregate initializer path. A local
aggregate is fine, and so is a scalar:

```c
char g1 = (char)0xFF;              /* correct */
char l1[2] = { (char)0xFF, 0 };    /* local: correct */
char a1[2] = { (char)0xFF, 0 };    /* file scope: 0 */
```

That split is what hid it: the obvious test is a local.

## Why it matters

Casting inside a static table is ordinary C, not a corner — flag tables,
lookup tables, and anything built from macros that cast:

```c
static const uint8_t mask[4] = { (uint8_t)0xF0, (uint8_t)0x0F, ... };
static const int limits[] = { (int)MAX_A, (int)MAX_B };
```

All of it silently becomes zeros. Nothing warns, nothing crashes, and a
zero-filled table usually *looks* plausible — the failure shows up far away as
a lookup returning the wrong answer.

## Fix shape

The static-initializer constant evaluator does not recognise the cast node.
Note that after
[[bug-cfront-plain-char-is-unsigned-and-folds-inconsistently]] a narrowing cast
lowers to a `((x & mask) ^ signbit) - signbit` **tree** (`CMakeNarrowIntCast`),
not a single node — so the fix is to make the static evaluator fold that shape
(and `AN_PTR_CAST` retagging), or to constant-fold the cast before it reaches
the initializer path. The tree predates this ticket: `pinned` builds the same
one and also yields 0, so folding it is the missing piece either way.

## Gate

Every row of the table above matches gcc, for file-scope arrays and structs,
with casts to `char` / `unsigned char` / `signed char` / `short` / `int` /
`long`, including values that truncate and values that do not. A local
aggregate with the same initializer keeps its current (correct) answer.
