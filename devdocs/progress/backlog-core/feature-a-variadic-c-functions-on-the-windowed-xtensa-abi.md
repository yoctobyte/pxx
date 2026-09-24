---
slug: feature-a-variadic-c-functions-on-the-windowed-xtensa-abi
track: A
prio: 30
type: feature
blocked-by: []
summary: "A C source that defines or reaches a variadic function refuses on windowed xtensa -- `variadic C functions on xtensa: only the call0 ABI is implemented` -- and ESP-IDF on the ESP32-S3 is windowed. crtl's own variadics (open, fcntl, the printf family) are reached by any C program that includes <stdio.h>, so C on the S3 IDF profile is refused wholesale; this is the wall that keeps C conformance on ESP to the C3 (riscv32). The refusal is deliberate and correct (guessing the windowed frame, argument window and incoming-stack bias yields wrong VALUES); what is missing is the implementation."
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
