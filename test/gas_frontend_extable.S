/* A kernel's user-memory access in GAS assembly (Rainyday ticket 0024's
   shape, as Linux's copy_user routines): stac/clac around the load, a fixup
   after the function, and an __ex_table entry pairing the faulting
   instruction with its fixup. tools/check_gas_frontend.sh step 6 checks the
   bytes and the __ex_table relocations against gas. */
	.text
	.globl	get_user_long
	.type	get_user_long, @function
/* long get_user_long(const long *uptr, long *out): 0, or -EFAULT (-14) */
get_user_long:
	stac
1:	movq	(%rdi), %rax
	clac
	movq	%rax, (%rsi)
	xorl	%eax, %eax
	ret
2:	clac
	movq	$-14, %rax
	ret
	.size	get_user_long, .-get_user_long

	.section __ex_table,"a"
	.balign	8
	.quad	1b, 2b
