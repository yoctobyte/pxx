# bugfix: cfront — sqlite3 aggregate crash from inline struct pointer field

**Track:** A+C  
**Status:** done
**Priority:** high

## Resolution

Fixed 2026-06-28. The original VdbeCursor/bitfield diagnosis was stale: direct
full-amalgamation probes now show PXX and GCC agree on `VdbeCursor` and the
nearby VDBE layouts.

The actual aggregate-query crash was in `findOrCreateAggInfoFunc`:

```c
struct AggInfo_func *pItem = pAggInfo->aFunc;
if( pItem->pFExpr==pExpr ) ...
```

`ParseCStructInto` handled inline nested aggregate members by value, but did not
handle declarators with stars after the closing brace:

```c
struct AggInfo_func { ... } *aFunc;
```

The parser skipped those pointer fields, so later `pAggInfo->aFunc` resolved as
offset 0. At runtime that read the first byte fields of `AggInfo` as a pointer,
producing a sign-extended bogus address and a segfault.

Fix: the inline nested aggregate branch now parses per-declarator `*`, records
`tyPointer` fields with the nested record as the pointee for one-star
declarators, uses pointer size/alignment for layout, and preserves by-value
nested aggregate behavior.

Guards:

- `test/cinline_struct_ptr_field_b129.c`
- `test/csqlite_extended_test.c` now completes through aggregate query:
  `COUNT`, `SUM`, `AVG`, and close all succeed.

## Problem

`/tmp/sq_full` — pxx-compiled sqlite3 amalgamation — crashes with SIGSEGV at
address 0x0 when exercised (crash at `0x4b74ab`, dereferencing a NULL `aOp`
field of `Vdbe`). Root cause investigation over two sessions points to struct
layout mismatches from the bitfield packing bug (see sibling ticket).

## Session work summary

- Session `d7edc492` (~2026-06-28 16:50):
  - Built `sq_full` from `library_candidates/sqlite/sqlite3.c` via pxx
  - Confirmed GDB crash: NULL pointer dereference in Vdbe VDBE operation
  - Disassembled caller at `0x4b73e6`, traced it to a field access at offset
    `0x88 = 136` into a struct, which is past what GCC says `VdbeCursor`
    should be (`sizeof = 120`)
  - Confirmed pxx computes `VdbeCursor.uc = 48`, `pKeyInfo = 56` on a simplified
    mock vs GCC's `uc = 40`, `pKeyInfo = 48`
  - Identified bitfield storage unit bug as root cause

- Current session `3c6d84a7` (~2026-06-28 18:07):
  - Verified `bftest.c` simplified struct gives matching results pxx vs GCC
    (`seekHit=6` for both) — so the packing is not always wrong, only in
    specific layout combinations involving the real VdbeCursor
  - Did NOT run `csqlite_layout_probe.c` against the full sqlite3.c — that is
    the first next step

## Next steps

1. Run `compiler/pascal26 -Ilib/crtl/src test/csqlite_layout_probe.c /tmp/probe && /tmp/probe`
   Compare output to GCC-compiled version:
   `gcc -Ilib/crtl/src library_candidates/sqlite/sqlite3.c test/csqlite_layout_probe.c -o /tmp/probe_gcc && /tmp/probe_gcc`
   (Note: GCC won't compile our crtl headers directly — use the approach from
   `sizes_gcc` that was built previously, or use `-DSQLITE_THREADSAFE=0` and
   standard headers.)

2. Fix the bitfield packing (see sibling ticket) and re-build `/tmp/sq_full`.

3. Verify the crash is gone.

## Files

- `test/csqlite_layout_probe.c` — layout probe test (exists)
- `test/csqlite_extended_test.c` — functional test (exists)  
- `library_candidates/sqlite/sqlite3.c` — the amalgamation
- `compiler/cparser.inc` — fix site
