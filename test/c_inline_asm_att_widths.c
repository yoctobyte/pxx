/* AT&T shapes through C inline asm, against gcc: movz/movs with both widths
   in the mnemonic, movslq, imul with an immediate, test with an immediate,
   %ah by name, movabsq. feature-gas-netbsd-libc-string-and-atomic-sources */
#include <stdio.h>
int main(void) {
  unsigned long a; unsigned b = 0x1234abcd; long c; int t; unsigned char by = 0xf0;
  __asm__("movzbq %1,%0" : "=r"(a) : "q"(by));
  __asm__("movsbq %1,%0" : "=r"(c) : "q"(by)); printf("%lx %ld\n", a, c);
  __asm__("movslq %1,%0" : "=r"(c) : "r"(-5)); printf("%ld\n", c);
  __asm__("imul $1000,%1,%0" : "=r"(c) : "r"(-7L)); printf("%ld\n", c);
  __asm__("xorl %0,%0; testb $0x80,%b1; setnz %b0" : "=&q"(t) : "q"(by)); printf("%d\n", t);
  __asm__("movl %1,%%eax; xchgb %%ah,%%al; movl %%eax,%0" : "=r"(t) : "r"(b) : "eax"); printf("%x\n", t);
  __asm__("movabsq $0x0101010101010101,%0" : "=r"(a)); printf("%lx\n", a);
  return 0; }
