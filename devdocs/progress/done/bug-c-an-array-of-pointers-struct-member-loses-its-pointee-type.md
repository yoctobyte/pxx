---
slug: bug-c-an-array-of-pointers-struct-member-loses-its-pointee-type
track: C
prio: 80
type: bug
status: done
created: 2026-11-25
found-by: Nodisx xz-utils recipe (claude-pxx): pxx's xz wrote stored (uncompressed) LZMA2 chunks, and LZMA1 output that did not decode
tags: [cfront, codegen, pointers, silent-wrong-code]
blocked-by: []
summary: "An element of an ARRAY OF POINTERS had no pointee type when the array was a struct member: `*s.a[i] = v` on `uint16_t *a[N]` stored 8 bytes (over three neighbours), a load read 4 or 8, `sizeof *s.a[i]` was 8, a double came back garbage and `s.a[i][j]` wrote somewhere else. Separately, and for array IDENTIFIERS too, pointer arithmetic on such an element (`a[i]++`, `a[i] + 1`, `s.a[i] += 1`) stepped ONE BYTE. Silent wrong code: xz's range encoder keeps `probability *probs[]` in a struct and emitted zeros. Fixed in the C shape readers; the stride half by 1ab372feb9 (CArrOfPtrElem, found via Xorg at the same time); test/c_array_of_pointers_member_pointee (gcc's output; the previous compiler got 13 of its 14 lines wrong)."
---

# An array-of-pointers member lost its elements' pointee type

## What was wrong

Two gaps in one shape, `T *a[N]`:

1. **Member arrays.** `CNodePtrDepth` and `CNodePtrBaseTk` refused array
   fields (`not UFldIsArray[fi]`), although the C struct builder records the
   element's pointer depth and base for an array member exactly as for a
   scalar one. The index arm only read the element's shape directly for an
   array IDENTIFIER. So `s.a[i]` was "a pointer to an 8-byte integer" and
   every dereference used that width.
2. **Strides.** `IRPointerStride` had arms for `p[i]` on a `T**` and for a
   field with a record base, but none for an element of an array of scalar
   pointers, member or not: the 1-byte default.

## Measured (gcc is the reference)

| | gcc | pxx before |
|---|---|---|
| `*s.a[0] = 9` on `uint16_t p[4] = {1,2,3,4}` | `9 2 3 4` | `9 0 0 0` |
| `sizeof *s.a[0]` (u8 / u16 / u32) | 1 / 2 / 4 | 8 / 8 / 8 |
| `*s.a[0] = 9.25` on `double *a[2]` | 9.25 | 4.4e-323 |
| `s.a[1][1] = 7` | stores into p[2] | no visible store |
| `a[0]++` (array identifier), bytes moved | 2 | 1 |

## Fix

- `CNodePtrDepth` / `CNodePtrBaseTk`: an array member reports its ELEMENT's
  depth and base (the convention array identifiers follow); the index arm
  reads an array member's element depth directly, so `T **a[N]` keeps 2.
- Strides: fixed independently by 1ab372feb9 (`CArrOfPtrElem`,
  bug-c-pointer-arithmetic-on-an-element-of-an-array-of-pointers-steps-bytes),
  which also covers `*a` and `*(a + i)`. The test here exercises it too.

Test: `test/c_array_of_pointers_member_pointee.c`, test-core row `c_aopmp26`.
With it, pxx's xz 5.6.3 compresses byte-identically to gcc's.
