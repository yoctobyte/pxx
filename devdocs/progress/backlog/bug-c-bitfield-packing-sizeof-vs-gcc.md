---
prio: 55
---

# bug: bitfield struct layout — sizeof disagrees with gcc (#pragma pack ignored?)

- **Track:** A/C (record layout — shared internals)
- **Found:** 2026-07-13 by the csmith differential fuzzer (`tools/csmith_fuzz.py`), while
  reducing the signed-bitfield miscompile (fixed in 63595f27).

## Repro

```c
#pragma pack(push, 1)
struct S2 { signed f0 : 20; signed f1 : 19; const volatile unsigned f2 : 18; signed f3 : 7; };
#pragma pack(pop)
int main(void) { printf("%d\n", (int)sizeof(struct S2)); }
```

gcc: `8`. pxx: `12`.

The four fields are 20+19+18+7 = 64 bits, so gcc packs them into exactly 8 bytes. pxx
allocates 12 — it is not packing adjacent bitfields into a shared storage unit across the
32-bit boundary (and/or is ignoring `#pragma pack`).

## Why it did not show up as a wrong VALUE

pxx's layout is self-consistent: it reads back every field it wrote, so the csmith
checksum came out right once sign extension was fixed. The bug bites where the layout is
OBSERVABLE:

- `sizeof` (above),
- `memcpy` / `memset` / union punning over the struct,
- any struct that crosses an ABI boundary to a gcc-built object (crtl, or a C library we
  link against),
- reading a bitfield struct out of a file or wire format written by a gcc-built program.

So it is a real interop bug, just not one the checksum oracle can see. Treat it as such:
correctness, not cosmetics.

## Notes for whoever takes it

- The C bitfield layout rule (System V x86-64 psABI): consecutive bitfields share a
  storage unit as long as the next field FITS in the current unit; a field that does not
  fit starts a new unit. `#pragma pack(N)` caps the alignment of the whole struct.
- Check `RecFieldBitShift` / `RecFieldBitBytes` / `IRBitStorageTk` in symtab.inc — the
  read/write lowering already keys off those, so a layout fix should flow through without
  touching IRLowerBitFieldRead/Store.
- Oracle: `gcc` on the same struct. `tools/csmith_fuzz.py` will exercise it broadly once
  the layout matches, since csmith emits packed bitfield structs constantly.
