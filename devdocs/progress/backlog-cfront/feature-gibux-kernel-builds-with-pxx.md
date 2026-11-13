---
track: A
tags: [C]
prio: 20
type: feature
blocked-by: []
summary: "Umbrella for Gibux, the owner's x86-64 kernel (githome:gibux, kept off GitHub): `make TOOLCHAIN=pxx test` in gibux/kernel must print `gibux: PASS (pxx)` from the same sources gcc builds. The inline asm and --emit-obj --freestanding parts are done, and so are va_arg under --freestanding and fs/procfs.c's parse error. File-scope initialisers are now .data (item 1), and all 30 kernel C files compile under --emit-obj --freestanding. `--link --freestanding -e start32` links an image that boots to user space (item 4; boot.S/entry.S still assembled by gas). Still open: (5) the .S (GAS) frontend; (6) an extern array declaration reserves .bss in every object."
status: open
owner: unassigned
---

# Gibux builds with pxx

The owner's rules for this work:

- GCC is the reference for C.
- Gibux must build under both gcc and pxx.
- Gibux gets no workarounds. pxx gains the features instead.

The request came through the peer session working on Gibux; its spec is
kept in this ticket's history.

Acceptance: in ~/gibux/kernel,

    make TOOLCHAIN=pxx PXX=<pascal26> test

must print `gibux: PASS (pxx)`, while `make TOOLCHAIN=gcc test` keeps
passing. The kernel Makefile's pxx lines are the assumed command lines:

- `--emit-obj --freestanding <src> <obj>`;
- `--link --freestanding --image-base=0xFFFFFFFF80100000 -o <elf> <objs>`.

## Done

[[feature-c-kernel-inline-asm-and-freestanding-objects-for-gibux]]:

- every inline asm in the kernel;
- `--emit-obj --freestanding` (no init/fini arrays, no crtl pulls, small
  .bss).

## Open, measured on kernel 64cc839 (rung 4), 2026-11-12

1. **DONE 2026-11-12** ([[feature-c-file-scope-initialisers-become-static-data]];
   on the way [[bug-c-aligned-on-a-global-variable-is-ignored]] and
   [[bug-c-a-block-scope-extern-with-no-file-scope-declaration-is-undeclared]]).
   All 30 C files of kernel e8ea914 compile with --emit-obj --freestanding.
   **File-scope initialisers run as code.** pxx keeps every C global in
   .bss and assigns its initial value in an init thunk (PendingInit /
   CAggInit, replayed by CompilePendingGlobalInits). A kernel has nothing to
   run a .init_array.
   - Refused under --freestanding: cpu.c, main.c, kmalloc.c, ramfs.c, file.c,
     tty.c, proc.c, syscall.c.
   - The forms involved:
     - `static char *p = "/"`;
     - `static char *argv[32] = { "/init", 0 }`;
     - `static const char *const names[32] = {...}`;
     - `static uint64_t v = VMALLOC_BASE` (a large unsigned constant);
     - struct initialisers with designators.
   - Needed: a static data image for initialised globals, with R_X86_64_64
     relocations for addresses of strings, functions and globals. gcc
     semantics, and a faster start-up for every C program too.
2. **DONE 2026-11-12** ([[bug-c-va-arg-fails-under-freestanding]]).
   **va_arg under --freestanding.** kprintf.c fails because
   `__pxx_va_arg_gp` is a pxx-internal runtime symbol. It came from a crtl
   pull, which --freestanding switches off. stdarg is compiler support, not
   libc, so the helper has to come with the compiler under --freestanding.
3. **DONE 2026-11-12** ([[bug-c-a-local-unsized-function-pointer-array-is-refused]]):
   it was a block-scope `long (*gens[])(..) = {..}`.
   **fs/procfs.c:268**: `expected C expression near size_t gen_pid_stat`. A
   C frontend parse gap; it still needs a repro.
4. **DONE 2026-11-12** ([[feature-link-freestanding-links-a-kernel-image]]):
   pxx-linked kernel booted under qemu to "Hello from user space" (status
   33). The kernel Makefile's pxx LINK line needs `-e start32`.
   **`--link --freestanding`** must:
   - supply no _start, with entry `start32` (or `-e sym`);
   - keep `.multiboot` (unreferenced) and place it first, in the first
     8 KiB;
   - define `__executable_start`, `_edata` and `_end`;
   - accept R_X86_64_32 and R_X86_64_32S;
   - take an image base at or above 2^63. `--image-base` refuses anything
     at or above 2^47 today, and the kernel is linked at
     0xFFFFFFFF80100000.

   Note that pxx's C code is already position-agnostic: only PC32 and
   R_X86_64_64 relocations, measured on every kernel object. It needs no
   code-model work for the higher half.
5. **DONE 2026-11-13** ([[feature-gas-frontend-assembles-dot-s-files]]): `pascal26 --emit-obj
   boot.S boot.o`; the whole kernel now builds with pxx alone and boots.
   **The .S frontend.** boot.S and entry.S are GAS (AT&T) assembly run
   through the C preprocessor. They need:
   - `.code32`/`.code64`;
   - `.section`, `.globl`, `.balign`, `.skip`;
   - `.long`/`.word`/`.quad` with symbols, expressions and label
     differences;
   - `.macro` with `\arg` substitution;
   - numeric local labels;
   - `ljmp $sel, $sym` and `movabsq`;
   - absolute-address operands, which become R_X86_64_32 in 32-bit code and
     R_X86_64_32S in 64-bit code.

   The inline-asm encoder and the AT&T operand reader can be reused. The
   object writer has to handle arbitrary sections.
7. **PARTLY DONE 2026-11-13** (in [[feature-link-freestanding-links-a-kernel-image]]):
   --freestanding emits no SSE (the variadic prologue's xmm spill is gone)
   and refuses the two red-zone code paths (alloca/VLA, FPU mask) instead of
   emitting them; the pxx-linked kernel is checked clean of both.
   Open: give alloca/VLA frame slots instead of the red zone, so a kernel
   may use a VLA; a float/double operation in --freestanding code is still
   emitted as SSE rather than refused.
   **Kernel code-generation constraints**, which the kernel Makefile lists
   as "pxx's equivalents are still to come":
   - gcc builds with `-mno-red-zone`, because an interrupt arrives on the
     same stack;
   - `-mgeneral-regs-only`, because user SSE state lives in the registers;
   - `-mcmodel=kernel`; pxx's PC32/R_X86_64_64-only code already covers it.
   Each of these still has to be checked against what pxx's x86-64 code
   generator emits.

6. **DONE 2026-11-13** ([[bug-c-an-extern-array-reserves-bss-in-every-declaring-object]]):
   the x86-64 object writer drops the import slots; the kernel image's .bss
   went from 5.6 MB to 3.7 MB.
   **`extern T big[N];` reserves .bss in every object** that includes the
   declaration. The symbol is correctly emitted UND, but the slot it was
   allocated is never released. proc.h's `extern struct proc procs[128]` is
   about 420 KB in each of about ten kernel objects. This is waste, not
   wrong behaviour.
