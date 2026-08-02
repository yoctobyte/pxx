---
track: C
prio: 50
type: bug
---

# `sizeof a[0]` is a parse error — the array-length idiom does not compile

- **Type:** bug (C frontend, parse) — **Track C**
- **Found:** 2026-08-02 by the Track B agent, writing a test that used
  `sizeof times / sizeof times[0]`.

## Measured

| expression | pxx | gcc |
| --- | --- | --- |
| `sizeof b` | 8 | 8 |
| `sizeof(b)` | 8 | 8 |
| `sizeof *a` | 4 | 4 |
| **`sizeof a[0]`** | **parse error** | 4 |
| `sizeof(a[0])` | 4 | 4 |
| **`sizeof a / sizeof a[0]`** | **parse error** | 4 |
| `sizeof(a)/sizeof(a[0])` | 4 | 4 |

So the unary form is supported, and so is a `*` dereference operand — it is
specifically the postfix **subscript** that the operand parser does not accept.
`error: unexpected token`, nothing more.

## Why it matters

`sizeof a / sizeof a[0]` is *the* way C spells "how many elements", usually
behind an `ARRAY_SIZE`/`countof` macro, and the unparenthesised form is at least
as common as the parenthesised one — K&R and most style guides write
`sizeof(a)/sizeof(a[0])`, but the Linux kernel, BSD sources and a great deal of
application code write it without. Any file using it fails to compile outright.

This is a loud failure, not a silent wrong value, which is the one merciful
thing about it.

## Fix shape

The operand of the unary `sizeof` form is a *unary-expression*, which in C
includes a postfix-expression — so `[]`, `.`, `->`, `++`/`--` and a call are all
legal there. The parser evidently accepts a primary plus a prefix `*` but does
not continue into the postfix chain. Worth checking the whole set at once rather
than adding `[]` alone: `sizeof s.field`, `sizeof p->field` and `sizeof f()` are
all valid C and likely fail the same way.

## Gate

Every row of the table above agrees with gcc, plus `sizeof s.field`,
`sizeof p->field`, and the array-length idiom used unparenthesised inside a real
`ARRAY_SIZE`-style macro.
