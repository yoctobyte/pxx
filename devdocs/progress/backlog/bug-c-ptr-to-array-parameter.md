---
summary: "C function PARAMETER of pointer-to-array type `int f(int (*q)[N])` / `(*q)[A][B]` doesn't set the row stride — q[i][j] mis-strides (single-dim) or fails to lower (multi-dim)"
type: bug
prio: 35
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
