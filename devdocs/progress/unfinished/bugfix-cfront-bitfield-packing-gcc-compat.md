# bugfix: C front — bitfield packing GCC-compatibility

**Track:** A+C  
**Priority:** high (blocks sqlite3 amalgamation correctness)

## Problem

pxx lays out bitfield storage units incorrectly compared to GCC.

When a struct has non-bitfield byte-sized members (`u8`) followed immediately by
bitfield members whose declared type is wider (`Bool isEphemeral:1` where
`Bool = unsigned int`), GCC **packs the bitfields into the unused bytes that
remain in the natural alignment gap** before the next wider-aligned field.
pxx instead allocates a fresh full 4-byte storage unit at the next alignment.

### Concrete example

```c
typedef int Bool;
typedef unsigned short u16;
typedef unsigned char u8;

struct VdbeCursor {
  u8 eCurType;   // 0
  i8 iDb;        // 1
  u8 nullRow;    // 2
  u8 deferredMoveto; // 3
  u8 isTable;    // 4
  Bool isEphemeral:1;   // GCC: packed into byte 5 (no separate storage unit)
  Bool useRandomRowid:1;
  Bool isOrdered:1;
  Bool noReuse:1;
  Bool colCache:1;
  u16 seekHit;   // GCC: offset 6  |  pxx: offset 8 (wrong!)
};
```

GCC output: `seekHit=6`  
pxx output: `seekHit=6` — CURRENTLY MATCHES for this test case (see below).

> **Correction from investigation:** the `bftest.c` probe showed pxx=6,
> GCC=6 — **they agree** for a `Bool isEphemeral:1` group following 5 u8s.
> The real discrepancy shown in the session was for the *actual* `VdbeCursor`
> in sqlite3.c which also has a `u16 seekHit` field **inside the bitfield
> group** (not just following it).

### Actual VdbeCursor layout (from sqlite3.c, line 23180)

```c
struct VdbeCursor {
  u8  eCurType;          // 0
  i8  iDb;               // 1
  u8  nullRow;           // 2
  u8  deferredMoveto;    // 3
  u8  isTable;           // 4
#ifdef SQLITE_DEBUG
  u8  seekOp;            // 5  (only in debug builds)
  u8  wrFlag;            // 6
#endif
  Bool isEphemeral:1;    // non-debug: starts at byte 5
  Bool useRandomRowid:1;
  Bool isOrdered:1;
  Bool noReuse:1;
  Bool colCache:1;
  u16  seekHit;          // GCC puts this at offset 6 (packed after bitfield byte at 5)
  union { Btree *pBtx; u32 *aAltMap; } ub;  // GCC: offset 8
  i64  seqCount;         // GCC: offset 16 (after 8-byte aligned ub)
  ...
  VdbeCursor *pAltCursor; // GCC: offset 32
  union { BtCursor *pCursor; ... } uc;  // GCC: offset 40
  KeyInfo *pKeyInfo;     // GCC: offset 48
};
```

GCC says `sizeof(VdbeCursor) = 120`, `uc = 40`, `pKeyInfo = 48`.  
pxx computed `sizeof = 72`, `uc = 48`, `pKeyInfo = 56` on a *simplified* mock
with `void*` union members but matching offsets. The full sqlite3.c struct
(`#include "sqlite3.c"`) must be tested directly.

## Root cause (hypothesis)

In `ParseCStructInto` (compiler/cparser.inc, ~line 5338):

When `isBitField = True`, pxx currently opens a new 4-byte storage unit at
`curOff` with **no alignment** (`bitUnitAlign := 1`), regardless of the
declared type. This means the storage unit can span bytes already occupied by
u8 fields if pxx advances `curOff` correctly, but the **seekHit field** (u16,
align=2) following the bitfield group forces an alignment step that pxx may
mis-handle — specifically: pxx places bitfield storage from the current `curOff`
onward, but when a non-bitfield follows it does `AlignTo(curOff, al)` where
`curOff` left off after the last used bit-byte. If pxx rounds up to 4 bytes
for the storage unit size rather than using only the actually-consumed bytes,
it will overshoot.

## What to investigate / fix

1. Compile `test/csqlite_layout_probe.c` (see test directory) against the full
   sqlite3 amalgamation and compare offset output between pxx and GCC.

2. In `ParseCStructInto`, the bitfield storage unit handling:
   - Currently: `bitUnitSize := 4; bitUnitAlign := 1` always.
   - GCC rule: the storage unit for bitfields of declared type `T` has size
     `sizeof(T)` and alignment `alignof(T)`. When fitting a bitfield `T f:n`
     into a run, GCC packs it into the *same* allocation unit as preceding u8
     fields if those bytes have space (i.e., the unit boundaries align with T).
   - Specifically: `Bool:1` declared as `unsigned int` starts a new 4-byte
     alignment-4 unit OR fits into slack bytes left by preceding fields if the
     unit boundary is satisfied. GCC seems to **not** start a new unit when
     the preceding bytes already fill to the bitfield storage unit's natural
     alignment boundary.

3. The correct fix is: when starting a new bitfield run, align `bitUnitOff`
   to `al` (the declared type's alignment) and set `bitUnitSize := sz`,
   not always 4 bytes with align 1. Then check whether consecutive bitfields
   can fit within that unit (up to `sz*8` bits).

4. Verify with `csqlite_layout_probe.c` and the full sqlite binary crashing
   test (`/tmp/sq_full`).

## Session history

- Session ending ~2026-06-28 17:01 (`d7edc492`) did the bulk of the
  investigation: confirmed GCC sizes for `VdbeCursor`, traced the crash in
  `/tmp/sq_full` to `NULL` dereference at a wrong field offset, pinpointed the
  pxx bitfield storage unit issue.
- Current session (~2026-06-28 18:07, `3c6d84a7`) confirmed `bftest.c`
  (simplified struct) gives matching results for pxx and GCC (both `seekHit=6`).
  Full sqlite3.c layout probe was not yet run — that is the next step.

## Files to touch

- `compiler/cparser.inc` — `ParseCStructInto` bitfield storage unit sizing
- `test/csqlite_layout_probe.c` — already exists, run it to validate
- Possibly `compiler/ir.inc` — `IRLowerBitFieldRead/Store` if the bit-shift
  metadata also needs updating
