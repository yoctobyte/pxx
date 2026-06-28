# C: `sizeof(array)` yields element size, not total array size

- **Type:** bug (C frontend → sizeof) — Track C
- **Status:** DONE (2026-06-28)
- **Owner:** unassigned
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]).

## Symptom

`sizeof` of a whole array returns the size of one element, so the standard
`ArraySize` idiom collapses to 1.

```c
static const char * const arr[] = { "a", "b", "c" };   /* 3 * 8 = 24 bytes */
int main(void){ return (int)(sizeof(arr) / sizeof(arr[0])); }  /* want 3, got 1 */
```

`sizeof(arr)` returns 8 (one `char*`) instead of 24, so `24/8`… `8/8` = 1.
Reproduces with and without `-Ilib/crtl/include`.

This is exactly sqlite's `sizeof(X)/sizeof(X[0])` count idiom
(`sqlite3CompileOptions`, many others), so it silently miscounts arrays.

## Likely cause

`sizeof` of an array identifier is treating the array as having decayed to a
pointer (element/pointer size), rather than using the array's declared total
size (element_size × element_count). Probably the same array-vs-pointer
type-size confusion behind
[[bug-c-addr-of-global-array-element-const-index-wrong-offset]].

## Acceptance

- `sizeof(array)` returns `element_size × count` for fixed/inferred-size arrays;
  `sizeof(array)/sizeof(array[0])` == count.
- Repro added to `test/` (exit-code oracle == 3).
- self-host byte-identical + cross unaffected (or full gate if shared).

## Log

- 2026-06-27 - Found reducing the sqlite compile (alongside the rejected
  invalid-symbol-in-lea false alarm). Confirmed real, include-independent.

## Resolution (2026-06-28, Track C+A)

`ParseCSizeof` already special-cased array identifiers, but whole arrays of
records still used `TypeSize(tyRecord)`, which is pointer-sized, rather than the
record element's `RecSize`. This made
`sizeof(localRecordArray)/sizeof(struct Record)` fold to zero for large records
such as SQLite's `sqlite3_vfs`.

Fixed whole-array sizing for record arrays and added
`test/clocal_static_record_array_b115.c`, which verifies both the array count
and the SQLite-shaped VFS registration loop.
