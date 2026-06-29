# C: `&global_array[const]` global pointer initializer computes wrong offset

- **Type:** bug (C frontend → global-init lowering) — Track C (+ A if shared
  address-of / reloc path)
- **Status:** done
- **Owner:** Codex
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up (side find while chasing
  [[bug-c-invalid-symbol-in-lea-sqlite]]).

## Symptom

A global pointer initialized to the address of an element of another global
array, with a constant index, stores the **wrong offset**.

```c
typedef unsigned char u8;
#define OP_Ne 52
const u8 tbl[300] = {1,2,3};
const u8 *p = &tbl[256-OP_Ne];          /* 256-52 = 204 */
int main(void){ return (int)(p - tbl); } /* expect 204; got 7 */
```

Got `7` (and `221` for a `[]`-inferred-size variant) instead of `204`. So the
constant index `256-OP_Ne` is folded/applied wrong when taking the address of a
global array element in a **global initializer** context. The element stride or
the const-index value is mis-handled.

This is the sqlite `sqlite3aLTb = &sqlite3UpperToLower[256-OP_Ne]` shape
(sqlite3.c:22764). It does **not** crash — it silently produces a wrong pointer
(unlike the separate [[bug-c-invalid-symbol-in-lea-sqlite]] which aborts).

## Notes

- Reproduces standalone (above), no extra context needed — easy to bisect.
- Variants: explicit size `[300]` → 7; inferred `[]` with initializer → 221.
  Both wrong, different wrong values → likely the index/stride math, not just a
  constant-fold miss.
- Compare against a non-global (local) `&arr[const]` to see if the bug is
  specific to the global-init reloc path or general.

## Acceptance

- `&global[const]` global pointer init stores the correct byte offset (element
  stride × index) for `char`/`u8` and wider element types.
- Standalone repro added to `test/` (exit-code oracle, e.g. `p - tbl == 204`).
- self-host byte-identical + cross unaffected (or full gate if shared path).

## Log

- 2026-06-29 - Closed as fixed by current constant-expression/preprocessor work:
  the standalone repro passes for both `u8` and `u16` element strides. Added
  `test/cglobal_array_elem_addr_b133.c` and wired it into `test-core`.
- 2026-06-29 - Picked up on Track A; reproducing with a standalone `u8`/`u16`
  global pointer initializer regression.
- 2026-06-27 - Found while reducing the sqlite invalid-symbol-in-lea crash; this
  is the non-crashing sibling on the same `&global_array[const]` construct.
