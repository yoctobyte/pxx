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
summary: "XTENSA DONE 2026-11-19 (rd): a top-level asm with .text and global labels assembles in place; each global label is a frameless function C can call (a prior prototype binds to it); entry/retw/call0/4/8/12 name (resolved after the unit, the slot keeps its n), local labels and two-register branches, .align/.space/.section .text*. All 10 Rainyday tests/xtensa programs now compile with pxx; signal, selfexe and fixed pass on the S3 kernel (fixed.c also needed bug-c-xtensa-object-data-puts-a-dead-runtime-string-and-const-arrays-ahead-of-user-data, done). OPEN: x86-64 and the other targets still refuse (rump repro s03: `.globl myfunc; myfunc: movl $42,%eax; ret`)."
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

## xtensa, done 2026-11-19 (rd)

CFsaEmitCodeXtensa (cparser.inc) runs when a file-scope asm on xtensa has
a `.text` line or a label. Each GLOBAL (.global/.globl/.weak) label opens a
procedure: found by name, so `void my_restorer(void);` before the asm binds
to it, or registered new. It is marked defined the way a C body is
(ProcExternal False, CProcHasLocalDef) and gets SetProcBodyAddrHere. The
lines up to the next global label are its body, through the inline-asm
xtensa engine (AsmXtensaProcessLine, labels scoped to the statement), plus:
- `entry aS, N` and `retw`/`retw.n`;
- `call0/4/8/12 name`: a CALLn slot recorded by name, resolved by
  CFsaResolveCalls just before ApplyCallFixups, which keeps the slot's n
  (CFsaCallSlotN) instead of the ABI's call8/call0;
- `.align N`, `.space/.skip/.zero N`, `.section`/`.pushsection` of .text or
  .text.* (one code stream), `.previous`/`.popsection`, `.type`/`.size`.
Anything else refuses. Not in the engine: BRI12 branches (beqz/bnez/bgez/
bltz), which none of Rainyday's tests use.

Measured: the 10 programs in Rainyday tests/xtensa all compile (were 7).
Linked with prog-fixed.ld and booted on the esp32s3 kernel in QEMU:
signal prints `signal: ok`, selfexe `selfexe: ok`. fixed.c's code layout is
right (far_main on the second 64 KiB page, past the 70000-byte pad); it
fails its data check, a different gap, ticketed separately.
test-xtensa row: xtensa/c_file_scope_asm_code (call0 ABI under qemu).

