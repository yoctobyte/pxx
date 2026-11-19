/* File-scope asm that DEFINES CODE on x86-64: global labels are functions
   (rump repro s03 is the first one), a numeric local label takes a branch,
   .p2align pads, `call name` reaches a C function defined further down and
   `jmp name` tail-calls it. Expected output is gcc's.
   feature-c-file-scope-asm-that-defines-code */
#include <stdio.h>
int myfunc(void);
int clamp0(int x);
int via_c(int x);
int tail(int x);
__asm__(".text\n.globl myfunc\n.type myfunc, @function\nmyfunc:\n\tmovl $42, %eax\n\tret\n"
        ".globl clamp0\nclamp0:\n\tmovl %edi, %eax\n\ttestl %eax, %eax\n\tjns 1f\n\txorl %eax, %eax\n1:\n\tret\n"
        ".p2align 4\n.globl via_c\nvia_c:\n\tsubq $8, %rsp\n\tcall twice\n\taddl $1, %eax\n\taddq $8, %rsp\n\tret\n"
        ".globl tail\ntail:\n\tjmp twice\n");
int twice(int x) { return 2 * x; }
int main(void)
{
    printf("%d %d %d %d %d\n", myfunc(), clamp0(-5), clamp0(9), via_c(21), tail(8));
    return 0;
}
