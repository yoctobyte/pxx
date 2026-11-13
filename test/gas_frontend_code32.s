# The GNU as frontend, 32-bit half: the instructions a multiboot kernel's
# entry runs before long mode (Gibux boot.S's shapes), encoded by the 64-bit
# encoder and checked against GNU as by tools/check_gas_frontend.sh --
# instruction text and relocations, after normalising encoding FORMS that
# print differently but mean the same (gas picks A3/83, pxx 89 04 25/81).
# A plain .s: no preprocessor, `#` comments.
        .set KVMA, 0xFFFFFFFF80000000
        .set FLAGS, 0x00010003

        .section .multiboot, "a"
        .balign 4
hdr:    .long 0x1BADB002
        .long FLAGS
        .long -(0x1BADB002 + FLAGS)
        .long hdr - KVMA
        .long entry32 - KVMA

        .text
        .code32
        .globl entry32
entry32:
        cli
        movl %ebx, %esi
        movl $(stack_top - KVMA), %esp
        movl $(pd - KVMA), %edi
        movl $(1 | 2 | (1 << 7)), %eax
        movl $512, %ecx
1:      movl %eax, (%edi)
        addl $0x200000, %eax
        addl $8, %edi
        loop 1b
        movl %eax, pd - KVMA + 8 * 3
        lgdt gdtp - KVMA
        movl %cr4, %eax
        orl $(1 << 5), %eax
        movl %eax, %cr4
        movl $0xC0000080, %ecx
        rdmsr
        orl $(1 << 8), %eax
        wrmsr
        movl %cr0, %eax
        andl $~(1 << 2), %eax
        movw $0x10, %ax
        movw %ax, %ds
        xorl %eax, %eax
        movl 4(%esi,%ecx,4), %edx
        ljmp $0x08, $(long64 - KVMA)
long64:
        hlt

        .data
        .balign 8
gdt:    .quad 0, 0x00AF9A000000FFFF
gdt_end:
gdtp:   .word gdt_end - gdt - 1
        .long gdt - KVMA

        .bss
        .balign 4096
pd:     .skip 4096
        .skip 4096
stack_top:
