/* A windowed _start for a pxx --emit-obj under qemu-xtensa: call8 check(),
   exit with its result (a10, the caller-side result register). */
    .text
    .global _start
    .align 4
_start:
    movi a1, stk_top
    movi a0, 0
    call8 check
    mov a6, a10
    movi a2, 118
    syscall
    .data
    .align 16
stk: .space 8192
stk_top:
