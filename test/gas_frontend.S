/* The GNU as frontend (gasfront.inc), 64-bit half: what a hand-written
   assembly file uses beyond one instruction -- the C preprocessor, sections,
   .globl, macros with arguments, numeric local labels, rip-relative data,
   a call into C (R_X86_64_PLT32), a .rodata table of code addresses
   (R_X86_64_64), a symbol difference folded to a constant, .rept, strings.
   Driven by gas_frontend_main.c; tools/check_gas_frontend.sh runs it
   assembled by pxx and by GNU as, and both must print the same. */

#define SCALE 3
#define BIAS  100

        .text
        .globl gas_sum, gas_count, gas_rip, gas_call_back, gas_pick, gas_strs, gas_span

/* gas_sum(a, b) = a * SCALE + b */
gas_sum:
        leaq (%rsi,%rdi,2), %rax
        addq %rdi, %rax
        ret

/* gas_count(n): loop n times with numeric labels, forward and back */
gas_count:
        xorl %eax, %eax
1:      testq %rdi, %rdi
        je 2f
        incq %rax
        decq %rdi
        jmp 1b
2:      ret

/* gas_rip(v) = v + BIAS, through two rip-relative data words */
gas_rip:
        movq %rdi, slot(%rip)
        movq slot(%rip), %rax
        addq bias(%rip), %rax
        ret

/* gas_call_back(v) = c_helper(v) + v: a call out to C */
gas_call_back:
        pushq %rbx
        movq %rdi, %rbx
        call c_helper
        addq %rbx, %rax
        popq %rbx
        ret

        .macro RET_CONST name, val
        .globl \name
\name:
        movl $\val, %eax
        ret
        .endm

        RET_CONST gas_seven, 7
        RET_CONST gas_big, (1 << 20) | 5

/* gas_pick(i) = gas_table[i]: code addresses in .rodata */
gas_pick:
        leaq gas_table(%rip), %rax
        movq (%rax,%rdi,8), %rax
        ret

        .section .rodata
        .balign 8
gas_table:
        .quad gas_seven, gas_big, gas_sum
gas_strs:
        .asciz "abc", "d\tef"
        .byte 1, 2, 'z'
        .word 0x1234
gas_span:
        .long gas_end - gas_table
gas_end:

        .data
        .balign 8
slot:   .quad 0
bias:   .quad BIAS
        .rept 3
        .long 0xdeadbeef
        .endr

        .bss
        .skip 64
        .section .note.GNU-stack, "", @progbits
