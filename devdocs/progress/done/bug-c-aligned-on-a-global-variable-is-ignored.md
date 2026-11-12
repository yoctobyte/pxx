---
track: A
tags: [C]
prio: 40
type: bug
blocked-by: []
summary: "`static uint8_t page[64] __attribute__((aligned(4096)));` got pxx's default alignment: the attribute was parsed and dropped for global variables. CDeclAttrAlign now reads it from the declaration's tokens and feeds AllocMinAlign plus the section alignment (ReqBssAlign / ReqDataAlign), so the object's .bss/.data carry it and the slot is placed on it."
status: done
owner: unassigned
---

# __attribute__((aligned(N))) on a global variable is ignored

Found 2026-11-12 in the Gibux kernel (page tables and FXSAVE areas need 4096
and 64). The attribute parser recorded the value (CAttrFlags bit 2 /
CAttrAlignValues), but ParseCGlobalVarDecl never read it.

## Fix

- `CDeclAttrAlign(typeIdx, endIdx)` (cparser.inc) scans the declaration for
  the attribute. Both the main and the function-pointer allocation paths use
  it.
- AllocVar/AllocArray honour `AllocMinAlign`.
- The writers align .bss to `ReqBssAlign` and, in objects, give .data/.bss
  `sh_addralign` from `ReqDataAlign`/`ReqBssAlign`.
- An executable cannot promise more than 16 for a data-resident global (the
  RO split keeps alignment only mod 16), so CPlaceGlobalInData refuses that
  case and the global stays in .bss, which is aligned.

## Test

test/c_file_scope_initialisers_are_data.c prints `page % 4096` and `fxa % 64`
(both 0), in all three modes.
