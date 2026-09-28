---
track: A
prio: 80
type: bug
blocked-by: []
status: done
found-by: frankD (Nil Python cross-target differential, 2026-09-28: the test corpus built for i386, aarch64 and arm32 at -O2, diffed against x86-64 and CPython)
summary: "With --xtensa-abi=windowed, a function returning a record whose result local lay more than 128 bytes into the frame did not compile ('aggregate-result frame offset out of range'): the hidden-result store was built with addi imm8 only. A 120 B record hit it, and so did lib/rtl/regex.pas ReRunAt (a ~170 B TReMatch), so no Nil Python program importing `re` built for the ESP32-S3."
owner: ""
---

# xtensa windowed: an aggregate result past 128 bytes of frame does not compile

Found on the S3: `import re` in any Nil Python program failed with
`target xtensa windowed: aggregate-result frame offset out of range`. The
reduced repro is a function that returns
`record ok: Boolean; n: Integer; a, b: array[0..13] of Integer end` (120 B)
through a local of that type. With 104 B it compiled. riscv32, x86-64 and xtensa
Call0 were fine.

## Mechanism

In windowed mode the hidden result pointer arrives in a2 and is stored to the
result local's frame slot, addressed from a15, before the parameter copy. The
address was formed with `addi a9, a15, off`, which takes -128..127, and any
larger offset hit `Error`. The Call0 arm uses `EmitFrameAddrXtensa`, which
materialises large offsets, but that helper bases on a7. In windowed mode, a7
is not the frame pointer yet at this point.

## Fix

`symtab.inc`: past imm8, the offset goes through `EmitLoadConstXtensa` (movi,
or a literal-pool l32r past ±2047) and `add a9, a15, a9`. That writes only a9,
so a2 stays intact.

## Test

`test-xtensa`, hosted (`--platform=posix --xtensa-soft-mulhigh`), with x86-64 as
the oracle:

- `test/test_xtensa_windowed_large_aggregate_result.pas` at 120 B, 1 KB and
  8 KB, under windowed and Call0;
- `test/test_xtensa_windowed_regex_search.pas`, which runs regex.pas (ReRunAt);
- a build-only row for Nil Python `import re` with the
  `examples/esp32/nilpy-s3/build.sh` flags.

On the compiler one commit back, the windowed builds fail.
