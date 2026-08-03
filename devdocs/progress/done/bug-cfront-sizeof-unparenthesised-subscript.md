---
track: C
prio: 50
type: bug
status: done
owner: claude-AC
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

## FIXED (2026-08-03)

Every row of the ticket's table now agrees with gcc, and so does the wider set
the "Fix shape" section asked to check at once.

The unparenthesised `sizeof ident …` branch had per-shape special cases (`.`/`->`
handled, `[` not). Replaced with a small **type-descriptor walk** over the
postfix chain — `cArrLen >= 0` means "array of cTk", `cRec` is the record when
cTk is a record, `cPtrTk`/`cPtrRec` the pointee when it is a pointer — so links
compose to any depth instead of needing a case per shape. `cOK` goes False the
moment a link cannot be resolved, leaving the pointer-size default rather than a
confidently wrong number.

Measured against gcc on the same file (all identical): `sizeof a[0]`,
`sizeof a / sizeof a[0]`, `ARRAY_SIZE(a)`, `ARRAY_SIZE(names)`, `ARRAY_SIZE(sa)`,
`sizeof s.buf`, `sizeof q->buf`, `sizeof sa[1]`, `sizeof sa[1].buf`,
`sizeof p[2].buf`, `sizeof q->next->buf`, `sizeof f()`.

**Multidimensional arrays were the trap.** `Syms[].ArrLen` is the FLATTENED
element count, so a naive "one subscript peels to the element type" gave
`sizeof m[0]` = 4 and `ARRAY_SIZE(m)` = 15 for `int m[3][5]` — swapping a loud
parse error for a silent wrong value, which is the worse failure. One subscript
now peels ONE dimension via `SymArrDimSpan` (gcc: 20 and 3, and pxx matches).
The spans of a multidim *record field* are not reachable by symbol index, so a
subscript into one bails to the default instead of guessing.

`sizeof f()` (size of the return type, argument list skipped unevaluated) landed
with it — same operand grammar, and it was the same parse error.

Pinned by `test/csizeof_postfix_unparen.c` (rc 42 under both gcc and pxx), wired
into the C suite.

## Log
- 2026-08-03 — resolved, commit PENDING.
