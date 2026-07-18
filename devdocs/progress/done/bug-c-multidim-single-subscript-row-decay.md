---
summary: "C `g[i]` on a multi-dim array (single subscript, row decay to a pointer) produced NULL/scalar-load -> SIGSEGV; fixed"
type: bug
prio: 40
---

# C: single-subscript row decay of a multi-dim array crashed (NULL pointer)

- **Type:** bug (Track C — C frontend multi-dim indexing, `cparser.inc`). Was a
  SIGSEGV / silent wrong value on valid C.
- **Found:** 2026-07-18, gcc-differential sweep while fixing
  [[bug-c-partial-multidim-array-index]].

## Repro

```c
static int g[6][4];
int main(void){ g[3][2] = 55; int *r = g[3]; return r[2]; }   /* want 55 */
```

- **gcc:** 55. **pxx (before):** SIGSEGV — `g[3]` (a single subscript on a >=2-D
  array = the C row decay to `int*`) evaluated to a scalar element load (0 =
  NULL), so `r[2]` dereferenced NULL. Same for 3-D (`int(*r)[4] = g[1]`) and for
  passing a row to a pointer parameter (`f(g[i])`).

## Root

The C multi-dim flatten branch (`cparser.inc`, `NodeArrNDInfo` path) required a
SECOND `[` to fire, so a single subscript fell through to the generic per-node
`AN_INDEX`, which strides by the element type and mis-decays the whole row to a
scalar. `NodeArrNDInfo` only fires for rank >= 2, and the partial-index branch
(from [[bug-c-partial-multidim-array-index]]) already builds the correct row
pointer for `nIdx < rank`.

## Fix (DONE)

Dropped the `(CurTok.Kind = tkLBrack)` (second-bracket) requirement from the ND
flatten entry, so a single subscript enters with nIdx=1 and, since rank >= 2,
takes the partial branch -> row pointer `&base + (i-lo0)*rowStride`. Full index
(all subscripts) and 2-of-N partials are unchanged (the while-loop still consumes
every present subscript). Rank-1 arrays never reach here (NodeArrNDInfo needs
rank >= 2) and keep the plain AN_INDEX path.

## Acceptance — MET

- Repro returns 55; 3-D row decay, deep partial (`g[1][2][3]` on `[2][3][4][2]`),
  and passing a row to an `int*` parameter all match the gcc oracle.
- C-conformance 220/220, self-host byte-identical. Regression test
  test/cmultidim_row_decay.c wired into `make test-c`.

## Log
- 2026-07-18 — resolved, commit f8a2cdde.
