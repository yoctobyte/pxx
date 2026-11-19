/* File-scope asm that DEFINES CODE (xtensa, call0 ABI here): each global
   label becomes a function C can call, local labels and branches work
   inside the statement, `.space` pads, and `call0 name` calls a C function
   defined further down. Rainyday's tests/xtensa entry stubs and signal
   restorer are this shape (windowed, call4). Expected output is gcc's
   arithmetic. feature-c-file-scope-asm-that-defines-code */
#include <stdio.h>

int add3(int x);
int clamp0(int x);
int via_c(int x);

__asm__(".text\n.align 4\n.global add3\nadd3:\n"
        "addi a2, a2, 3\nret\n"
        ".global clamp0\nclamp0:\n"
        "movi a3, 0\nbge a2, a3, .Lpos\nmovi a2, 0\n.Lpos:\nret\n"
        ".space 64\n.align 4\n"
        ".global via_c\nvia_c:\n"
        "addi a1, a1, -16\ns32i a0, a1, 0\ncall0 twice\n"
        "addi a2, a2, 1\nl32i a0, a1, 0\naddi a1, a1, 16\nret\n");

int twice(int x) { return 2 * x; }

int main(void)
{
    printf("%d %d %d %d\n", add3(4), clamp0(-5), clamp0(9), via_c(21));
    return 0;
}
