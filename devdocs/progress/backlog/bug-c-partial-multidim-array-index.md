---
summary: "C frontend rejects a partial multi-dimensional array index (g[i][j] on int g[..][..][..]) — valid C, gcc accepts"
type: bug
prio: 45
---

# C frontend: partial multi-dim array index rejected ("wrong number of array subscripts")

- **Type:** bug (Track C — C frontend; `cparser.inc` multi-dim flattening). Valid C
  rejected (compile fail), not a miscompile.
- **Status:** backlog
- **Found:** 2026-07-17, csmith differential run (seed 700023, bucket
  `PXX_COMPILE_FAIL`) — filed by a Track-A+ agent into the owning lane per the
  T-owns-the-tool rule.

## Repro (minimal)

```c
static int g[2][9][7];
int main(void) {
  int (*row)[7] = g[1][3];   /* partial index: 2 of 3 dims -> int(*)[7] */
  row[0][2] = 77;
  return g[1][3][2];         /* 77 */
}
```

- **gcc:** compiles, result 77.
- **pxx:** `error: wrong number of array subscripts` near `row`.

A *full* index (`g[i][j][k]`, all 3 dims) works fine; so does a single `g[i]`. Only a
**partial** multi-index (more than one subscript but fewer than the declared rank) is
rejected. The csmith program hit the same error path in a larger expression.

## Root

`cparser.inc:2374-2394` flattens chained subscripts on a known multi-dim array to one
row-major `AN_INDEX`. It parses subscripts `while (CurTok = '[') and (nIdx < NDInfoNDims)`
then hard-requires `nIdx = NDInfoNDims` (line 2388), erroring otherwise. A partial index
(`nIdx < NDInfoNDims`) is valid C — it decays to a **pointer to the remaining sub-array**
(`g[1][3]` on `int[2][9][7]` is `int(*)[7]`) — but this branch only models the
full-rank element access.

## Fix direction

On a partial index (`nIdx < NDInfoNDims`), instead of erroring, produce the **sub-array
pointer**: `base + flatidx(nIdx) * stride(remaining dims)`, typed as a pointer-to-array
of the remaining shape, so subsequent `[...]` / deref work. The existing
`BuildFlatNDIndex` computes the row-major offset for the supplied subscripts; the
remaining stride is the product of the un-indexed dimension spans. Element type / rank
bookkeeping must reflect the residual dimensions.

## Acceptance

- The repro compiles and returns 77; csmith seed 700023 compiles.
- A `test/` C case for a partial multi-dim index (assign through the sub-array pointer,
  read back full-index).
- Gate: C tests green + self-host byte-identical.

## Note

Found by `tools/csmith_fuzz.py` (pxx vs gcc). 24/30 seeds agreed; this was the lone
`PXX_COMPILE_FAIL`. Reproduces from the seed exactly.
