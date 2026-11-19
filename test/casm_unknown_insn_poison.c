/* An instruction pxx's x86 assembler lacks, in inline asm of a routine gcc
   never emits, must not stop the compile: rump's x86/include/cpufunc.h has a
   static inline invpcid nobody calls (rump-pxx g20). The routine is poisoned
   instead; tools/check_casm_unknown_poison.py checks that a real call still
   refuses, and that a non-static routine still stops the compile.
   bug-c-asm-in-an-unused-static-inline-function-stops-the-compile */
#include <stdio.h>

struct desc { unsigned long a, b; };

/* operands after the unknown word, and a second instruction after it */
static inline void bogus(long op, unsigned long va)
{
	struct desc d = { 1, va };
	__asm volatile("frobnicate %[d],%[op]\n\tnop" : : [d] "m" (d), [op] "r" (op) : "memory");
}

/* no operands at all */
static inline void bogus0(void) { __asm volatile("frobnicate; nop"); }

/* a static inline nobody calls, calling a poisoned one: it inherits the
   poison (gcc -O0 would emit a plain static one, and refuse too) */
static inline void middle(void) { bogus(1, 2); bogus0(); }

/* known asm beside them keeps working */
static inline int add1(int x) { __asm volatile("addl $1, %0" : "+r"(x)); return x; }

int main(void)
{
	printf("%d\n", add1(41));
	return 0;
}
