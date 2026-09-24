---
slug: feature-a-variadic-c-functions-on-the-windowed-xtensa-abi
track: A
prio: 30
type: feature
blocked-by: []
summary: "DONE 2026-09-24. Variadic C DEFINITIONS build and run on windowed xtensa (the ESP-IDF esp32s3 ABI): seen from the callee a call8's args are in a2..a7 like call0's and the frame base is a15; only the incoming-stack bias differs (32 vs 16). The one shape still refused: a variadic returning an aggregate BY VALUE (hidden result pointer at arg word 0, not modelled). ESP objects on windowed also got an app_main -> main entry stub. c-testsuite on esp32s3 under QEMU: 216 pass, 3 fail, 1 skip of 220.""
---

# Variadic C on windowed xtensa

Found 2026-09-24 (frankS) bringing up `feature-c-esp-conformance-coverage`.

## Measured

`compiler/pascal26 --target=xtensa --xtensa-abi=windowed --platform=esp
-Ilib/crtl/include -Ilib/crtl/src hello.c hello.o` for a `printf` hello:

```
error: variadic C functions on xtensa: only the call0 ABI is implemented.
  The windowed frame pointer, argument window and incoming-stack bias all
  differ ...   in: lib/crtl/src/fcntl.c
```

The first wall is crtl's own `fcntl`/`open` (`int open(const char *, int, ...)`),
reached before the program's printf. So the unit of work is va_start/va_arg
over the windowed incoming area, not anything in the user's program.

## What it unblocks

The S3 leg of `tools/run_c_conformance_esp.sh`, which is written for esp32c3
only and says so; adding it is a chip switch plus the hello-s3 project once
this lands. For scale, the C3 at the same tree: 218 pass, 1 fail, 1 skip of 220.

## 2026-09-24 (frankS): DONE

- cparser.inc variadic prologue: windowed arm addresses the save area off a15
  explicitly (EmitFrameAddrXtensa answers a7, which is still arg word 5 at
  that point), overflow at a15+32. Refused: variadic + aggregate result.
- cparser.inc: windowed ESP-object entry stub (entry a1,64; argc=0/argv;
  init; main; finalizers; retw) at .text+0, where the writer exports app_main.
- Proven by booting, not by building: `tools/run_c_conformance_esp.sh --chip
  esp32s3` (new; Makefile test-c-conformance-esp32s3). First full run at
  compiler 17be23f99ad8: 209/10/1. Every red but 00053 was a real bug, fixed in
  the same commit and re-run at f8f9d3f827d3: xtensa signed-only integer
  compare and quos/rems for unsigned; the windowed fenv stub lacking `entry`
  (%f truncated); 64-bit branch truthiness testing the low word only; and a
  harness artefact (renamed main loses C99's fall-off-returns-0). Left red:
  00053 (p50 struct-tag bug), 00175 (C implicit double->int, next), 00207
  (VLA: alloca unsupported on xtensa).
- Guards: test-emit-obj rows (variadic builds, entry bytes 36 81 00, the
  aggregate refusal); pinned v416 refuses the variadic row.
