---
slug: feature-c-file-scope-asm-that-defines-code
track: C
prio: 35
type: feature
status: backlog
created: 2026-11-19
found-by: rd (Rainyday kernel seat), building Rainyday's tests/xtensa with pxx
tags: [cfront, inline-asm, file-scope-asm, xtensa, rainyday, rump]
blocked-by: []
summary: "File-scope asm() that defines code (`.text; .global _start; _start: entry a1,32; call4 cmain`) is refused: pxx handles only symbol aliases and strings there (feature-c-file-scope-asm-symbol-aliases). It blocks 3 of Rainyday's 10 tests/xtensa programs (fixed.c, selfexe.c, signal.c) and the rump repro s03. Needs an asm chunk in .text outside any procedure, its labels as object symbols visible to C, calls from it into C procedures, and on xtensa entry/call4/call8/retw in the text engine."
---

# C: file-scope asm that defines code

## What is refused, measured 2026-11-19 (pxx c3abb0c8bf)

`pascal26 --target=esp32s3 --freestanding --emit-obj` on Rainyday's
tests/xtensa (origin/main 5728916): 7 of 10 compile. The local register
variables they all use landed in c3abb0c8bf, and those 7 boot as init on the
S3 kernel and print ok. The other three stop at:

    C: file-scope asm: ".text" -- pxx handles symbol aliases (.globl/.weak,
    a = b, .set) and .ident/.gnu.warning strings there; ...

| file | the asm | needs |
|---|---|---|
| selfexe.c | `_start: entry a1,32; addi a6,a1,32; call4 cmain` | a global label, entry, call4 to a C function |
| signal.c | `my_restorer: movi a2,225; syscall`, address taken from C | a global label that C references (`extern void my_restorer(void)`) |
| fixed.c | as selfexe, then `.section .text.pad,"ax"; .space 70000; far_main: entry; mov; call4 cmain; retw; .previous` | .section/.previous/.space, retw, a call that must reach 70000 bytes |

x86-64 has the same gap (rump repro s03: `.globl myfunc; myfunc: movl $42,%eax; ret`).

## What it takes

1. **A code chunk outside any procedure.** It is emitted into .text, is a
   DCE root, and its global labels become object symbols (FUNC, GLOBAL or
   WEAK as declared). A C declaration of the same name resolves to it, in
   --emit-obj and in a linked image.
2. **Calls from the chunk into C:** `call4 cmain` / `call0` / `call8`
   (xtensa) and `call foo` (x86-64) through the existing call fixups, with
   their reach rules. A call that must reach past the call0/call4 window
   (fixed.c's 70000-byte pad is there to test that) needs the long form.
3. **The xtensa text engine:**
   - It encodes none of entry, call0/4/8 to a symbol, callx, or retw today
     (AsmXtensaLineKnown).
   - Labels are block-scoped, at most 32 per block.
4. **Directives:**
   - `.text`, `.section .text.*` and `.previous` select this chunk.
   - `.align N` pads with nops or zeros.
   - `.space N` reserves N zero bytes.
   - Anything else is refused by name, as today.

Lockstep: Rainyday builds these tests with gcc today. The kernel itself builds
with pxx and needs none of this.
