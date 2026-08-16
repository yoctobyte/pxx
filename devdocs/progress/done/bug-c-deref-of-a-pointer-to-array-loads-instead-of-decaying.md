---
track: C
prio: 45
type: bug
blocked-by: []
summary: "`*m` on `int m[3][4]` (and `*(t[1]+2)` on a 3-D one) emits a LOAD. In C, dereferencing a pointer-to-array yields the array, which decays right back to the same address — a no-op. `**m` fails to compile and `*(*(t[1]+2)+3)` segfaults."
status: done
owner: claude-acpn
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

## Fixed 2026-08-16 (same session, right after the stride ticket)

Three pieces, because the level is what decides and nothing carried it:

1. **`CDerefDecayStride`** answers what `*x` steps by, or 0 for an ordinary
   load. It walks the pointer-arith chain to its base identifier and reads the
   LEVEL off the outermost `ASTSLen` stamp: no stamp = the whole array, a stamp
   = however many dimensions have been stepped through. At the last level the
   answer is 0 and the deref stays a real load, which is what keeps
   `*(m[1]+1)` reading an int.
2. **`CNodePointeeTk`** types that load: a decayed row is a raw byte add with
   nothing on it that says `char`, so the default `tyInteger` made `*s[1]` come
   back 25699 instead of `'c'`.
3. **`IRPointerStride`** steps a pointer-to-array variable by its whole pointee
   (`int (*r)[4]`, `r + 2` is 32 bytes) — the same rule the decayed array
   already obeys. `r[i][j]` is unaffected: that path flattens the subscripts
   itself.

`test/carr2d_decay_stride.c` grew twelve assertions covering `**m`, `*m[2]`,
`**s`, `*s[1]`, `***t`, `*(*(t[1]+2)+3)`, `*(*(*(t+1)+2)+3)`, the row as a
string, and the three pointer-to-array forms; it returns 42 under both gcc and
pxx.

## Log
- 2026-08-16 — resolved, commit b617b0672.
