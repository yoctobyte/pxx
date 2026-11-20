---
slug: feature-c-accept-rainydays-gcc-kernel-cflags
title: "Rainyday's gcc kernel CFLAGS run through pxx unchanged, each meaning what gcc means or refused"
track: C
type: feature
prio: 45
status: done
owner: claude-dupwt
found: 2026-11-20
found-by: rd (Rainyday arch.mk: "pxx's equivalents are still to come")
---

# Rainyday's gcc kernel CFLAGS through pxx

## Before

Rainyday's x86-64 gcc compile line is

    $(CC) -std=c11 -O2 -Wall -Wextra -ffreestanding -fno-pic \
          -fstack-protector-strong -mstack-protector-guard=global \
          -mno-red-zone -mcmodel=kernel -mgeneral-regs-only \
          -fno-asynchronous-unwind-tables -fno-builtin $(INCLUDES) -c $< -o $@

Through pxx, only -O2 (and since 4fb6638f1f the two protector flags) was
accepted. `-c` and `-o` were unknown options. The -std/-W/-f ones were unknown
too. The three -m ones fell into the "-m = Pascal mode" branch ("unsupported
Pascal mode"). Rainyday's pxx build therefore had its own line, and arch.mk
said the SSE / red-zone / code-model equivalents were "still to come".

## What each flag means now

| flag | pxx |
| --- | --- |
| `-c` | = `--emit-obj` |
| `-o <file>` | the output, before or after the source (`-c src.c -o out.o`); with `-o`, nothing else may follow the source |
| `-ffreestanding` | = `--freestanding`, plus gcc's `__STDC_HOSTED__ 0` (pxx's own `--freestanding` keeps the 1 it always reported) |
| `-std=c99/c11/c17` (+ `gnu`, `c9x/c1x/c18`, `iso9899:`) | `__STDC_VERSION__` 199901L / 201112L / 201710L; the non-gnu forms define `__STRICT_ANSI__`, as gcc does. c89/c90/c2x refused |
| `-W<anything>` | accepted, no effect (diagnostic selection only; `-Werror` keeps its meaning). `-Wl,` `-Wa,` `-Wp,` refused |
| `-fno-pic/-fno-pie` | accepted: no GOT, data reached PC-relative or absolute-64 |
| `-fno-asynchronous-unwind-tables`, `-fno-unwind-tables` | accepted: pxx emits no .eh_frame |
| `-fno-builtin[-x]` | accepted: pxx substitutes nothing for a call by its library name |
| `-mno-red-zone`, `-mgeneral-regs-only` | accepted with `-ffreestanding`/`--freestanding` on x86-64, where they are TRUE; refused hosted ("hosted pxx code and its runtime use the red zone" / "...uses the SSE registers for float") and on other targets |
| `-mcmodel=kernel`, `-mcmodel=small` | accepted on x86-64; kernel defines `__code_model_kernel__`. medium/large refused |

## Why the three -m flags are true, measured

- **SSE.** `--freestanding` already refuses float arithmetic ("--freestanding:
  float/double arithmetic is not supported ... (gcc: -mgeneral-regs-only)"). It
  also skips the XMM half of the va_list save.
- **Red zone.** The alloca park moved to frame slots for Rainyday earlier. The
  only code left that touched SSE or the red zone was the C fenv stubs
  (`__pxx_fegetround`/`__pxx_fesetround`: stmxcsr/ldmxcsr at `[rsp-4]`). Every
  C object carried them, gc'd at link time but present. They are no longer
  emitted under `--freestanding` (nothing freestanding has the float
  formatter that calls them).
- **Code model.** Every relocation in a pxx x86-64 object is `R_X86_64_PC32`
  or `R_X86_64_64`, never the 32-bit absolutes. That is valid in the top 2 GiB
  (kernel) and in the low 2 GiB (small) alike.

All 93 Rainyday kernel C files were compiled with their gcc line verbatim
(`-fno-stack-protector` appended for canary.c, as arch.mk does). The objects
are **byte-identical** to the same files built with
`--emit-obj --freestanding -O2` plus the protector flags. A disassembly of all
93 finds **no** access below rsp and no XMM register in compiled code. The one
`ldmxcsr` is `-0x10(%rbp)` in fpu.c's own inline asm. Relocations:
40,366 PC32 and 3,453 R_X86_64_64, nothing else.

## Rows (test-core, beside the stack-protector rows)

test/c_gcc_kernel_cflags.c is built with the Rainyday line. Static asserts
check the predefines; objdump finds 0 below-rsp/SSE hits; readelf finds 0
relocations other than PC32/64. The positive control is a hosted object,
whose scan must be > 0 (it is 521). Two more rows: `-std=gnu11` reports
201112 in a hosted executable, and the `-mno-red-zone` (hosted) and
`-mcmodel=large` refusals print their messages.

## Not done

- Rainyday's arch.mk still has its own pxx line. Switching it is Rainyday's
  call. With this, `TOOLCHAIN=pxx` can reuse the gcc `COMPILE` line with
  `CC=pascal26`.
- `-nostdlib`, `-static`, `-Wl,...` (their gcc LINK line) are not touched.
  pxx's `--link` stays its own spelling.
