# SSE2 integer moves, logic, shifts and shuffles, and the AES-NI/PCLMUL
# byte forms mbedTLS's aesni.c writes: pxx's encoding must be gas's, byte
# for byte (feature-c-inline-asm-sse-and-aes-ni).
	.text
	.globl	sse_forms
sse_forms:
	movdqu	(%rdi), %xmm0
	movdqu	16(%rsi), %xmm9
	movdqu	-32(%r12,%rcx,4), %xmm15
	movdqu	%xmm0, (%rdi)
	movdqu	%xmm11, 0x100(%r13)
	movdqu	%xmm1, %xmm2
	movdqu	%xmm8, %xmm3
	movdqa	(%rax), %xmm4
	movdqa	%xmm5, 8(%rsp)
	movdqa	%xmm1, %xmm2
	movdqa	%xmm14, %xmm7
	movq	16(%rdi), %xmm1
	movq	(%r9), %xmm10
	movq	%xmm1, (%rdi)
	movq	%xmm12, 24(%r8)
	movq	%xmm3, %xmm4
	movq	%rax, %xmm5
	movq	%xmm6, %r11
	pxor	%xmm1, %xmm0
	pxor	%xmm9, %xmm10
	pxor	(%rdx), %xmm2
	por	%xmm3, %xmm1
	por	%xmm13, %xmm2
	pand	%xmm4, %xmm5
	pand	32(%rbx), %xmm6
	pandn	%xmm7, %xmm8
	psllq	$1, %xmm1
	psllq	$63, %xmm9
	psrlq	$63, %xmm3
	psrlq	$7, %xmm12
	pslldq	$8, %xmm3
	pslldq	$4, %xmm11
	psrldq	$8, %xmm4
	psrldq	$1, %xmm15
	psllw	$3, %xmm1
	psrlw	$3, %xmm2
	psraw	$2, %xmm3
	pslld	$5, %xmm4
	psrld	$5, %xmm10
	psrad	$31, %xmm5
	pshufd	$0xff, %xmm1, %xmm1
	pshufd	$0x55, %xmm2, %xmm2
	pshufd	$0x1b, %xmm8, %xmm14
	pshufd	$0xaa, (%rsi), %xmm3
	.byte	0x66,0x0F,0x38,0xDC,0xC1
	.byte	0x66,0x0F,0x3A,0xDF,0xC8,0x1B
	.byte	0x66, 0x0F, 0x3A, 0x44, 0xD0, 0x11
	ret
