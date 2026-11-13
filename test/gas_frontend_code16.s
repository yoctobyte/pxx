# .code16 in the GNU as frontend (compiler/gasfront.inc), checked against GNU
# as by tools/check_gas_frontend.sh: the 16-bit instruction text and every
# relocation must match gas's. The shape is an SMP AP trampoline (Gibux's
# arch/x86_64/trampoline.S): real mode, then .code32, then .code64, all in
# one section, with addresses written as TRAMP + (label - start).
# .text has no branches, so it must come out BYTE-IDENTICAL to gas's (gas
# relaxes branches to rel8; pxx keeps rel16). The branches sit in .text.br
# and are compared as instruction text. The .code32 line uses %ecx and the
# .balign an explicit fill byte, because .code32's absolute accumulator
# moves (gas: moffs A1) and gas's multi-byte NOP padding are encoded
# differently by pxx; that is a known difference, and the .code32 check
# normalises it.
	.text
	.code16
	.globl tramp16
tramp16:
	cli
	cld
	xorw %ax, %ax
	movw %ax, %ds
	movw %ax, %es
	movw %ds, %ax
	movw $0x1234, %bx
	movl $0x12345678, %ebx
	movw %cs, %ax
	movl %eax, %ebx
	addw $1, %ax
	addl $1, %eax
	orl $1, %eax
	andw $0xfff0, %sp
	incw %ax
	incl %eax
	pushw %ax
	pushl %eax
	popw %ax
	popl %eax
	pushfl
	popfl
	pushf
	popf
	lgdtl 0x7000 + (gdtp - tramp16)
	lidtl 0x7000 + (gdtp - tramp16)
	lgdt gdtp
	movl %cr0, %eax
	movl %eax, %cr0
	movl %cr4, %ecx
	movl %ecx, %cr4
	movl 0x7000 + (cr3v - tramp16), %eax
	movl %eax, 0x7000 + (cr3v - tramp16)
	movw 0x7000 + (cr3v - tramp16), %ax
	movl cr3v, %edx
	movl (%eax), %ebx
	movw 4(%ebx), %cx
	movl 8(%esp), %eax
	movl %eax, (%edi,%esi,4)
	leal 3(%eax), %ecx
	inb $0x92, %al
	outb %al, $0x92
	inw %dx, %ax
	inl %dx, %eax
	wrmsr
	rdmsr
	hlt
	movl $0xC0000080, %ecx
	xorl %edx, %edx
	testl %eax, %eax
	cmpw $5, %ax
	shll $4, %eax
	shrw $1, %ax
	retl
	ret
	lret
	lretl
	iret
	iretl
	movsw
	movsl
	stosw
	lodsl
	cbtw
	cwtl
	cwtd
	cltd
	ljmpl $8, $0x7000 + (t32 - tramp16)
	ljmp $0, $0x7000 + (t16b - tramp16)
	ljmpw $0, $0x7000 + (t16b - tramp16)
t16b:
	.code32
t32:
	movw $16, %ax
	movw %ax, %ds
	movl 0x7000 + (cr3v - tramp16), %ecx
	movl %ecx, %cr3
	ljmp $24, $0x7000 + (t64 - tramp16)
	.code64
t64:
	movq 0x7000 + (cr3v - tramp16), %rsp
	movabsq $tramp16, %rax
	jmp *%rax
	.balign 8, 0
gdtp:
	.word 31
	.long 0x7000 + (gdtp - tramp16)
cr3v:
	.long 0

	.section .text.br, "ax", @progbits
	.code16
br16:
	jmp br16
	jz br16
	jnz br16b
	call br16
	loop br16
	loopl br16
	jcxz br16
	jecxz br16
	calll br16
br16b:
	ret
