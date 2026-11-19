---
slug: bug-a-c-function-sections-identity-row-is-red-since-function-sections-implies-static-data
track: A
prio: 30
type: bug
status: done
created: 2026-11-19
owner: claude-dupwt
tags: [emit-obj, test, x86-64]
blocked-by: []
summary: "test-emit-obj's c_function_sections row links a plain object and a --function-sections object and asserts the allocatable sections are identical (elf_alloc_same.sh). It was red: .text 269876 vs 253468, .data 15592 vs 17520. On x86-64, --function-sections also turns on CStaticDataMode by default (compiler.pas, the toybox 9.47 MB -> 1.69 MB change), which bakes C initialisers into .data instead of running stores, so the two binaries differ by design. The flagged arm now passes --no-c-static-data, and the identity holds again (5 allocatable sections identical). The row is about relocated calls, and that is still what it measures."
---

# c_function_sections identity row red since --function-sections implies static data

Found 2026-11-19 running test-emit-obj for the i386 weak-call change. The row
was red before that change: the object built with the flag differs because
of the static-data default, not because a relocated call resolved anywhere
else.

Measured with `--no-c-static-data` on the flagged arm: both binaries print
13, and elf_alloc_same.sh reports 5 allocatable sections identical with
only the two thunk symbols added (plus the STT_FILE name, which the row
avoids by reusing one object path).
