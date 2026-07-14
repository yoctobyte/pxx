---
prio: 60
resolved: fb342151
---

# bug: UNION bitfields packed sequentially like struct bitfields (silent wrong bits)

- **Track:** C (cfront)
- **Found:** 2026-07-14 by the csmith differential fuzzer (seed 3 checksum divergence
  vs the gcc oracle), after its crash was fixed. Filed already-fixed — the board is
  the record.

## What was wrong
Union bitfield members accumulated `bitUnitUsed` exactly like struct bitfields, so

```c
union U1 { unsigned f0; unsigned f1 : 14; unsigned f2 : 14; int f3; };
```

placed `f2` at bits 14..27 instead of overlapping `f1` at bit 0. Reads and writes
of `f2` touched the wrong bits — **silent wrong values**, no crash: csmith seed
3's per-global checksums pinned it to `g_176.f2/f3` in minutes
(`./t_gcc 1 | diff - <(./t_pxx 1)`).

## Fix (fb342151, b352)
In the union arm of the bitfield layout in `ParseCStructInto`, every member
starts its own storage unit: `bitUnitOff := 0; bitUnitUsed := 0; thisOff := 0`
unconditionally (C: each union member is its own declaration at offset 0).
Struct bitfields keep packing. Regression test
`test/cunion_bitfield_overlap_b352.c` (union + struct control, output
byte-identical to a gcc-built binary's), wired into test-core.
