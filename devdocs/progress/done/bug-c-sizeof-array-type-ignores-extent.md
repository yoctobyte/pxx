---
summary: "C `sizeof(int[10])` returns the element size (4), not 40 — sizeof of an array TYPE-NAME ignores the extent (silent wrong value)"
type: bug
prio: 35
---

# C: `sizeof(array-type)` ignores the array extent

- **Type:** bug (Track C — C frontend, `ParseCSizeof` / `ParseCDeclType` in
  `cparser.inc`). Silent wrong value.
- **Found:** 2026-07-18, gcc-differential sweep.

## Repro

```c
#include <stdio.h>
int main(void){
  printf("%lu %lu %lu %lu\n",
    sizeof(int[10]), sizeof(char[5]), sizeof(int[2][3]), sizeof(double[4]));
  return 0;
}
```

- **gcc:** `40 5 24 32`.
- **pxx:** `4 1 4 8` — every `sizeof(TYPE[N])` returns just the ELEMENT size; the
  array extent(s) are dropped.

## Root

`ParseCSizeof` type branch does `tk := ParseCDeclType; sz := CTypeSizeBytes(tk)`.
`ParseCDeclType` captures a trailing `[N]` only for typedef-inherent arrays
(`CTypeTypedefArrLen`) and pointer-to-array declarators — NOT for an abstract
array type-name like `int[10]`, so the extent never reaches the size calc. (Same
missing "abstract-array-extent capture" as [[bug-c-pointer-to-multidim-array-declarator]].)

## Fix direction

Have `ParseCDeclType` record an abstract trailing `[N][M]..` dim list; in the
`sizeof` type branch multiply `CTypeSizeBytes(tk)` by the product of the extents.
Rare in real code (usually `sizeof(var)` / `sizeof(type)`), but silent.

## Acceptance

- The repro prints `40 5 24 32`; C-conformance 220/220 + self-host byte-identical.
- A `test/*.c` regression.

## Log
- 2026-07-18 — resolved, commit ec713264.
