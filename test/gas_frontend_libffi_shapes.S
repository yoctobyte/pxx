/* SPDX-License-Identifier: Zlib */
/* The shapes libffi's x86/unix64.S and win64.S need from an assembler,
   written fresh (not libffi's code). tools/check_gas_frontend.sh step 7
   assembles it with pxx (also under --shared-runtime) and with gcc and wants
   the same .text and .eh_frame bytes and the same relocations.
   Padding uses an explicit 0xcc fill: gas reads 0x90 as "NOPs" and writes multi-byte ones. */

/* a macro whose expansion holds its own name after a dot (ffi_cfi.h's
   `#define cfi_startproc .cfi_startproc`): the paint byte must
   not split `.globl` (bug-gas-the-preprocessor-paint-byte-splits-an-asm-token) */
#define globl .globl
#define SEH(...)
#define ENTRY(BASE, X) .balign 8, 0xcc; .org BASE + (X) * 8

	.text
	globl shapes
	SEH(.seh_proc shapes)
shapes:
	/* relaxation: short and long, forward and backward (feature-gas-what-libffi-x86-assembly-needs) */
1:	jmp	2f
	je	1b
	jne	.Lfar
	.fill	150, 1, 0x90
.Lfar:	jl	1b
	jmp	external_fn
	jg	external_fn
2:	ret

	/* a jump table checked with .org label + constant (feature-gas-what-libffi-x86-assembly-needs) */
	.balign 8, 0xcc
.Ltable:
ENTRY(.Ltable, 0)
	ret
ENTRY(.Ltable, 1)
	movd	%xmm0, (%rdi)
	jmp	2b
ENTRY(.Ltable, 2)
	fstpt	(%rdi)
	jmp	2b
ENTRY(.Ltable, 3)
	movsd	%xmm0, (%rdi)
	ret
ENTRY(.Ltable, 4)

	/* SSE and x87 forms (feature-gas-what-libffi-x86-assembly-needs,
	   feature-gas-what-libffi-x86-assembly-needs) */
	movd	%xmm3, 8(%rsp)
	movd	(%rsi), %xmm1
	movd	%eax, %xmm2
	movd	%xmm5, %ecx
	movd	%xmm9, (%r12)
	fstpt	16(%rdi)
	fldt	(%rsi)
	fldt	16(%r9)
	movsd	8(%rsi), %xmm1
	movsd	%xmm2, %xmm3
	movss	%xmm0, (%rdi)
	movss	(%rax), %xmm12
	movsd
	cmpsd

	/* indirect branches through memory (feature-gas-what-libffi-x86-assembly-needs) */
	call	*16(%rbp)
	jmp	*8(%rax)
	call	*(%r12)
	jmp	*-8(%r13,%rcx,8)
	call	*slot(%rip)
	call	*%r11
.Lend:
	ret

	.data
slot:	.quad	0

	/* a hand-written unwind table: @unwind (feature-gas-what-libffi-x86-assembly-needs),
	   lengths as forward equates (feature-gas-what-libffi-x86-assembly-needs) and X - .
	   (feature-gas-what-libffi-x86-assembly-needs) */
	.section .eh_frame,"a",@unwind
	.set	.Lset0, .Lecie - .Lscie
	.long	.Lset0
.Lscie:	.long	0
	.byte	1, 0x7a, 0x52, 0
.Lecie:
	.set	.Lset1, .Lefde - .Lsfde
	.long	.Lset1
.Lsfde:	.long	.Lsfde - .Lscie
	.long	shapes - .
	.long	.Lend - shapes
	.quad	.Lfar - .
.Lefde:
