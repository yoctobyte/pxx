---
track: C
prio: 45
type: bug
blocked-by: []
summary: "`*m` on `int m[3][4]` (and `*(t[1]+2)` on a 3-D one) emits a LOAD. In C, dereferencing a pointer-to-array yields the array, which decays right back to the same address — a no-op. `**m` fails to compile and `*(*(t[1]+2)+3)` segfaults."
---

# Dereferencing a pointer-to-array loads instead of decaying

- **Type:** bug (crash / refusal) — **Track C** (`compiler/cparser.inc`, the
  unary `*` path).
- **Found:** 2026-08-16, alongside
  [[bug-c-a-multidim-array-decays-with-the-element-stride]], which fixed the
  strides but not this.

## Measured

```c
int m[3][4]; int t[2][3][4];
printf("%d\n", **m);                  /* gcc 0   — pxx: does not compile */
printf("%d\n", *(*(t[1]+2)+3));       /* gcc 9   — pxx: SIGSEGV          */
```

`(*(m+1))[2]` is fine, because the subscript form takes another path — so the
gap is exactly "`*` applied to something whose pointee is an array".

## Why

`*p` lowers to an AN_DEREF that LOADS pointer-width from the address. That is
right when the pointee is a scalar or a record, and wrong when the pointee is
an ARRAY: C's rule is that the result is the array object, which immediately
decays to a pointer to its first element — same address, no memory access. So
the load reads the first 8 bytes of the row as if they were an address and
jumps into them.

## Where to fix

The unary `*` in `ParseCUnary`. When the operand is (a) a multi-dim array
identifier, or (b) a pointer carrying a pointee array shape (`SymPtrElemArrLen`
> 0, or the ASTSLen stride the partial-index builder now stamps), `*x` is `x`
with the pointer type stepped down one dimension — the same thing `x[0]` builds
today, which is the ready-made normal form to reuse rather than a second path.

## Gate

`test/carr2d_decay_stride.c` extended with `**m`, `*(*(t[1]+2)+3)` and
`*(s+1)` on a `char[2][8]`, diffed against gcc; `tools/gate.sh quick`.
