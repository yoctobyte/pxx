# The assembly half of tools/check_link_freestanding.sh, shaped like Gibux's
# arch/x86_64/boot.S: a multiboot-style header in its own .multiboot section
# that names __executable_start, _edata and _end through 32-bit absolutes
# (R_X86_64_32, physical = virtual - KERNEL_VMA), 32-bit entry code, a
# .rodata table, and a call into C.
	.set KERNEL_VMA, 0xFFFFFFFF80000000

	.section .multiboot, "a"
	.balign 4
	.globl mb_header
mb_header:
	.long 0x1BADB002
	.long mb_header - KERNEL_VMA
	.long __executable_start - KERNEL_VMA
	.long _edata - KERNEL_VMA
	.long _end - KERNEL_VMA
	.long start32 - KERNEL_VMA

	.section .rodata
	.globl ktable
ktable:
	.quad kmain
	.quad ktable

	.text
	.code32
	.globl start32
start32:
	movl	$(boot_stack_top - KERNEL_VMA), %esp
	.code64
	.globl start64
start64:
	movq	$0x2BADB002, %rdi
	leaq	ktable(%rip), %rsi	# reached, so section GC keeps .rodata
	call	kmain
1:	hlt
	jmp	1b

	.bss
	.balign 16
	.skip 4096
boot_stack_top:
