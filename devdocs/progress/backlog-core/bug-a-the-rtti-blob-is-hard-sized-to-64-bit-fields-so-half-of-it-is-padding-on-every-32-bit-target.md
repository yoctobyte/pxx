---
slug: bug-a-the-rtti-blob-is-hard-sized-to-64-bit-fields-so-half-of-it-is-padding-on-every-32-bit-target
track: A
prio: 50
type: bug
status: new
created: 2026-09-20
found-by: frankS
blocked-by: []
summary: "RTTI_CLS_SIZE = 128 with the comment `all fields 8 bytes', and it is the same 128 on every target -- so on riscv32, xtensa, i386, arm32 and wasm32 every pointer field carries 4 bytes of padding. THE DIFFERENTIAL IS MEASURED, not inferred: PXXDBG=a.datamap reports `class RTTI headers 10240B' for the NilPy print demo compiled for x86-64 AND for riscv32 --platform=esp, byte-identical, 80 headers either way. On ESP that 10,240 B is SRAM, 8.1% of our 125,832 B, and roughly half of it is padding a 32-bit target cannot use. Pascal VMT slots are the same shape (`vmtN * 8' in pasparser_prog.inc) -- 1,848 B here, ~924 of it padding. It is a SIZE bug and not a correctness one: DataPutZeros zeroes the slot and the target is little-endian, so a 4-byte pointer read back as 8 is correctly zero-extended. THE LAYOUT IS SPELLED THREE TIMES and that is the real obstacle -- the emitter (rtti_emit.inc), `PXX_RTTI_*' in compiler/builtin/builtin.pas, and `RTTI_OFS_*' in lib/rtl/rtti.pas -- so narrowing the stride means changing three files that no test forces to agree. Ceiling, not estimate: up to ~5,120 B on this program, less if some fields must stay 8 bytes."
---

# The RTTI blob is hard-sized to 64-bit fields, so half of it is padding on every 32-bit target

Found 2026-09-20 while categorising ESP SRAM under
[[umbrella-an-esp32-image-is-as-small-as-it-can-be]]. It is on the owner's
stated axis — *"SRAM here is most relevant"* — and unlike every code-removal
rung, which measures at **zero SRAM from here**, this one is SRAM by
construction.

## The layout

`compiler/defs.inc`:

```pascal
{ RTTI blob byte layouts (all fields 8 bytes) }
RTTI_CLS_SIZE    = 128; { name,parent,instSize,vmt,propCount,props,methCount,meths,
                          fieldCount,fields,ifaceCount,ifaces,unitName,classInfo,
                          flatCount,flatBases }
RTTI_PROP_SIZE   =  64; { 8 fields }
RTTI_IFACE_SIZE  =  32;
```

Sixteen fields, eight bytes each, **one constant for all seven backends**. Half
of those fields are pointers, and a pointer on riscv32, xtensa, i386, arm32 or
wasm32 is four bytes.

## The measurement, and it is a differential rather than an inference

`PXXDBG=a.datamap` on `examples/esp32/nilpy-c3/main/main.npy`, compiler at
`734c1df1e`:

```
x86-64 hosted                     class RTTI headers  10240B
riscv32 --platform=esp --dce      class RTTI headers  10240B
```

**Byte-identical across a 64-bit and a 32-bit target.** 10,240 / 128 = 80
classes get a header (of 113 total; records are excluded). The size did not
move because nothing about it is target-aware.

On ESP that 10,240 B is SRAM — **8.1% of our whole 125,832 B**, measured on the
chip with `examples/esp32/nilpy-c3/build.sh sram`.

Pascal VMTs have the same shape: `pasparser_prog.inc` reserves `vmtN * 8` bytes
per VMT, so a slot is eight bytes whatever a pointer costs. `a.datamap` reports
1,848 B of VMT on this program, ~924 of it padding on a 32-bit target.

## NOT a correctness bug, and worth saying why

The emitter writes a 4-byte pointer into an 8-byte slot that `DataPutZeros` has
already zeroed, and the targets are little-endian, so a reader taking eight
bytes gets the pointer correctly zero-extended. Nothing reads garbage. This is
purely bytes.

**And no ISR hazard applies**, which separates it from everything on
[[feature-a-there-is-no-read-only-load-segment-so-nothing-can-be-flash-resident]]'s
REMAINING list: the blob stays in `.data` exactly where it is, it just stops
being twice the size it needs. No structure moves to flash, so the
cache-off-in-an-interrupt question does not arise.

## The real obstacle: three spellings of one layout

- the **emitter**, `rtti_emit.inc`, which writes fields at `+0`, `+8`, `+16`, …
- `PXX_RTTI_*` in `compiler/builtin/builtin.pas` (`PARENT = 8`, `INSTSIZE = 16`,
  `METHCOUNT = 48`, `UNITNAME = 96`, `CLASSINFO = 104`, `FLATCOUNT = 112`,
  `FLATBASES = 120`)
- `RTTI_OFS_*` in `lib/rtl/rtti.pas` (`NAME = 0`, `PARENT = 8`,
  `METHCOUNT = 48`, `METHS = 56`)

Three mechanisms serving one concept is the threshold
`devdocs/dev/root-cause-over-microfix.md` calls a design flaw, and **nothing
forces the three to agree** — a stride change that updates two of them produces
a runtime that reads the wrong field and no compile error. That, not the
arithmetic, is the work.

The bootstrap constraint the header documents still applies and is the reason
this is not a free edit: the compiler must be able to read a blob the *previous*
stage's emitter wrote. `defs.inc`'s own note argues that class blobs are safe
from this because the compiler declares no class type and calls no class-blob
accessor — **re-verify that by grep before relying on it**, because it is
exactly the kind of checkable claim that decays.

## What would retire this

Fields sized from `TARGET_PTR_SIZE` in all three spellings, DERIVED from one
place rather than restated, plus a test that a 32-bit and a 64-bit build report
*different* `a.datamap` RTTI totals for the same program — the differential
above, inverted into a guard. **Today that guard would be red; after the fix
the two numbers must differ, and asserting equality is what the current code
would pass.**

State the win as a ceiling: **up to ~5,120 B on this program**, less for any
field that must stay 8 bytes (`instSize` and the counts are candidates to keep
if anything relies on their width). Measure after, not before.
