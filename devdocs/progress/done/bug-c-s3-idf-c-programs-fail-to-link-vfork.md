---
slug: bug-c-s3-idf-c-programs-fail-to-link-vfork
title: "Every C program on the ESP32-S3 under IDF failed to link: undefined vfork"
track: C
type: bug
prio: 80
status: done
owner: claude-dupwt
found: 2026-11-19
found-by: rerun of feature-c-esp-conformance-coverage (S3 leg, initial IDF build)
---

# S3 under IDF: undefined `vfork` from crtl's system()/popen()

## Before

Since 4099c798f4 (2026-11-17, a real vfork on xtensa for Rainyday),
crtl's `system()` and `popen()` call `vfork()` under
`#if defined(__xtensa__) && defined(__linux__)`, and crtl's own
`vfork() { return fork(); }` is compiled out under the negation. The body is
written by the compiler (EmitCVforkStub), but only for xtensa on
PLATFORM_POSIX. `__linux__` is predefined on EVERY target (cpreproc.inc), IDF
included, so on the S3 under IDF nothing defined vfork:

    libpxx_app.a(main.o): in function `popen': undefined reference to `vfork'
    libpxx_app.a(main.o): in function `system': undefined reference to `vfork'

crtl is linked whole into a C program's object, so this was every C program
on the S3 under IDF, not only those that call system(): the c-testsuite
harness's hello image did not link, so the S3 leg ran zero tests. C3
(riscv32) was unaffected.

## Change

The compiler predefines `__PXX_VFORK_STUB__` on the condition its two
EmitCVforkStub sites test (xtensa and PLATFORM_POSIX), and crtl's three
guards (stdlib.c system, stdio.c popen, unistd.c the fork fallback) test that
macro. One condition, written in one place beside the predefine, so crtl
and the compiler cannot disagree about whether vfork exists.

`__linux__` itself stays unconditional; narrowing it is a wider change.

## Measured

- S3/IDF: the conformance harness links again; 00001, 00040, 00100, 00207
  PASS (4/4). Full S3 leg rerun recorded in feature-c-esp-conformance-coverage.
- xtensa Linux: tools/check_xtensa_vfork.py OK (the real vfork still used).
- Gate quick GREEN.
