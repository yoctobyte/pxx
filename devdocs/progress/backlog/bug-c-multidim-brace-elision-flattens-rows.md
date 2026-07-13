---
prio: 50
---

# bug: multidim brace elision flattens rows — partial rows are not zero-filled

- **Track:** C (cfront)
- **Found:** 2026-07-13, csmith fuzzer, while fixing b309. **PRE-EXISTING** — the pinned
  stable compiler behaves identically, so it is not a regression from that work.

## Repro

```c
int q[2][3] = {{1},{2}};
/* gcc: q[0][0]=1  q[0][1]=0  q[1][0]=2   (each brace fills ONE row, tail zeroed) */
/* pxx: q[0][0]=1  q[0][1]=2  q[1][0]=0   (the braces are flattened, row boundaries lost) */
```

C99 6.7.8p21: a nested brace group initializes exactly one sub-aggregate, and the rest of
that sub-aggregate is zeroed. pxx's multi-dim brace pre-scan concatenates the element
lists and ignores the row boundaries, so a SHORT row bleeds the next row's values into it.

Silent: wrong values, no diagnostic.

## Scope

Ordinal element types (INT arrays) as well as the pointer arrays fixed in b309 — the
flattening pre-scan is shared. Only bites when a nested brace group is SHORT (a full
initializer flattens to the same thing, which is why it went unnoticed).

## Where

`compiler/cparser.inc`, the local multi-dim brace pre-scan (~line 3580 onward): it walks
the token stream counting scalars and skipping `{`/`}` as if they were noise. It has to
track the dimension it is in and pad each nested group out to that dimension's span
(the recursive walker `CInitWalkArray` already knows how to do this — the pre-scan is the
one that doesn't).
