---
prio: 55
---

# `#pragma pack` is IGNORED — struct layout silently differs from gcc

- **Type:** bug (C frontend — record layout; silent ABI mismatch)
- **Track:** C — C frontend (record layout) — file-lane A for `symtab.inc` layout code
- **Status:** done
  `bug-c-bitfield-packing-sizeof-vs-gcc` and blamed the bitfield storage-unit algorithm.
  **That diagnosis was wrong**, and anyone following it would have rewritten code that is
  already correct. See "What the old ticket got wrong" below.

## The defect
`#pragma pack(N)` is parsed away and has no effect on layout.

```c
#pragma pack(1)
struct A { char c; int i; };     /* gcc: 5   pxx: 8 */
#pragma pack()
struct B { char c; int i; };     /* gcc: 8   pxx: 8  (agree) */
```

**Struct A contains no bitfields at all.** The alignment cap that `pack` imposes is simply
not applied: every field keeps its natural alignment, so `i` is padded to offset 4 instead
of sitting at offset 1.

This is an ABI mismatch, and a silent one — the struct compiles, runs, and has the wrong
size and the wrong field offsets. Any packed on-disk/on-wire structure (file headers,
network frames, hardware register maps, anything a real C corpus does with `#pragma pack`)
is laid out wrong with no diagnostic.

## What the old ticket got wrong (verified 2026-07-14)
It claimed the bitfield storage-unit algorithm was at fault and pointed at
`RecFieldBitShift`. Measured against gcc on six varied bitfield structs — `:3/:5`,
`:31/:2`, `char + int:5`, a `:0` separator, `long long:40 + :20`, `char:4/:4/short:9` —
**pxx and gcc agree on every one.** The bitfield layout is gcc-identical.

The original repro (`packed=8` vs gcc's `packed=8` -> a bitfield struct under `pack`) mixed
the two things together and blamed the wrong one: it is `pack` that is missing, and the
bitfields in that struct were incidental.

## Wanted
- Honour `#pragma pack(N)` / `#pragma pack(push, N)` / `#pragma pack(pop)`: cap each
  member's alignment at N, and cap the record's own alignment at N.
- `__attribute__((packed))` is the same knob and should land with it.
- Apply to bitfield storage units too (they take the cap like any other member) — but note
  the bitfield algorithm itself needs no change.

## Repro / gate
The four-struct program above must match gcc's `sizeof` for all four, plus a field-offset
check (size alone can coincide). Then the C corpus: `tools/run_c_conformance.sh` green, and
the real corpora (sqlite/zlib/lua/tcc) unchanged.

## Log
- 2026-07-14 — resolved, commit 56365087.
