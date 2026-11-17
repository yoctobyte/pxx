    .text
    .global _start
_start:
    movi a1, stk_top
    call0 check
    mov a6, a2
    movi a2, 118
    syscall
    .data
    .align 16
stk: .space 4096
stk_top:
