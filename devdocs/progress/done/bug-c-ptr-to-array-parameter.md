---
summary: "MULTI-dim ptr-to-array param `int f(int (*q)[A][B])` fails to lower (AN_BINOP/kind-5 gap). Single-dim `int (*q)[N]` FIXED in 85c233a2."
type: bug
prio: 30
---

## UPDATE 2026-07-18 (85c233a2)

Single-dim pointer-to-array params `int (*q)[N]` are FIXED — the param path now
records SymPtrElemArrLen/NDims/dims onto the param symbol (test
`test/cptr_to_array_param.c`, `at(m[1],2,3)`=123, was 110). What REMAINS is only
the **multi-dim** param `int (*q)[A][B]`: it now parses (declarator dim capture
landed with the local fix) but fails at IR lowering with `IR_UNSUPPORTED: AST node
kind 5 (AN_BINOP)` on the `q[i][j][k]` flatten in the param body — a deeper
lowering gap distinct from the shape capture. Clean compile error, no miscompile,
never worked. Retargeted to that residual.

---

# C: pointer-to-array function parameters mis-stride / don't lower

- **Type:** bug (Track C — C frontend param declarators, `cparser.inc`). Wrong
  value (single-dim) / compile fail (multi-dim). Valid C.
- **Found:** 2026-07-18, while fixing [[bug-c-pointer-to-multidim-array-declarator]]
  (which fixed the LOCAL-variable form).

## Repro

```c
int m[3][4][5];
int f1(int (*q)[5])   { return q[2][3]; }    /* single-dim ptr-to-array param */
int f2(int (*q)[4][5]){ return q[0][2][3]; } /* multi-dim ptr-to-array param  */
int main(void){ /* fill m ... */ return f1(m[1]) + f2(&m[1]); }
```

- **gcc:** both correct (q strides by the row size).
- **pxx:** `f1` returns the wrong value — `q[2][3]` mis-strides because the
  PARAMETER symbol never gets `SymPtrElemArrLen` set (unlike a local
  `int (*q)[5]`), so the pointer-to-array `p[i][j]` flatten in ParseCPostfixTail
  doesn't fire and it strides as a plain pointer. `f2` (multi-dim) fails with
  `IR_UNSUPPORTED` at lowering.

## Root

Local pointer-to-array declarators set `SymPtrElemArrLen` (and, since 77fb51df,
`SymPtrElemNDims` + `SymArrDimSpan` for multi-dim) in ParseCLocalDeclAST. The
function-parameter declarator path does NOT — it parses `(*q)[N]` without
recording the pointee array shape on the param symbol.

## Fix direction

In the C parameter parser, when a param declarator is a pointer-to-array
(`CTypePtrElemArrLen > 0` after ParseCDeclType), copy the same fields onto the
param symbol that the local path sets: `SymPtrElemArrLen`, `SymPtrElemNDims`, and
the per-dim spans into `SymArrDimSpan[idx*MAX_ARR_DIMS+d]`. Then the existing
ParseCPostfixTail flatten (single- and multi-dim) works for params unchanged.

## Acceptance

- f1/f2 match gcc; C-conformance 220/220 + self-host byte-identical.
- A `test/*.c` regression (single- and multi-dim ptr-to-array params).

## Log
- 2026-07-18 — resolved, commit 27cb6404.
