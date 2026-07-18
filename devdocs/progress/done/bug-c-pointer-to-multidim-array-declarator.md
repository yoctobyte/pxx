---
summary: "C declarator `int (*p)[A][B]` (pointer to a >=2-D array) not parsed — blocks using a partial multi-dim index that leaves >=2 dims"
type: bug
prio: 30
---

# C frontend: pointer-to-multidim-array declarator `int (*p)[A][B]` rejected

- **Type:** bug (Track C — C frontend declarator parsing, `cparser.inc`). Valid C
  rejected (compile fail), not a miscompile.
- **Found:** 2026-07-18, while fixing [[bug-c-partial-multidim-array-index]].

## Repro

```c
int gg[4][5][6][3];
int main(void){
  int (*p2)[6][3] = gg[2];   /* partial index, 1 of 4 -> int(*)[6][3] */
  p2[4][5][2] = 99;
  return gg[2][4][5][2];      /* 99 */
}
```

- **gcc:** compiles, 99.
- **pxx:** `error near: p2` — the declarator `int (*p2)[6][3]` (pointer to a 2-D
  array) is not parsed. `int (*p)[N]` (pointer to a 1-D array) IS supported
  (SymPtrElemArrLen), so only the multi-dimensional inner array shape is missing.

## Relation to the partial-index fix

[[bug-c-partial-multidim-array-index]] (fixed de649c39) makes a partial multi-dim
index produce the correct sub-array **address** for any number of remaining dims.
But when >=2 dims remain (`gg[2]` -> `int(*)[6][3]`), there is no way to DECLARE
the target pointer type, so the value is unusable. Single-remaining-dim partials
(`g[1][3]` -> `int(*)[7]`) work end to end today. This ticket closes the >=2-dim
gap.

## Fix direction

Extend the C declarator parser to accept a bracket run after `(*name)`:
`(*p)[A][B]...` should record the full inner array shape (spans A,B,..) on the
pointer symbol — generalise SymPtrElemArrLen to a dim list (as UFldArr* /
SymArrDim* already do for arrays) so `p[i][j][k]` strides by the right sub-array
sizes.

## Acceptance

- The repro compiles and returns 99; partial index leaving >=2 dims is usable.
- Gate: C-conformance stays 220/220 + self-host byte-identical.

## Log
- 2026-07-18 — resolved, commit 5dbc89df (was 77fb51df pre-rebase).
