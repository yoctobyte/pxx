/* _start for the freestanding riscv32 object checks: call check() and exit
   (Linux exit, a7 = 93) with its low byte, under qemu-riscv32 user mode.
   The stack is in .data; link with --no-relax, since gp is never set.
   tools/check_riscv32_freestanding_struct.py */
    .text
    .globl _start
_start:
    la sp, stk_top
    call check
    andi a0, a0, 255
    li a7, 93
    ecall
    .data
    .align 4
stk: .space 8192
stk_top:
