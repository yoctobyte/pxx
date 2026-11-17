/* File-scope initialisers a freestanding object must carry as DATA: nothing
   runs before the kernel's own entry. Scalars, a 64-bit value, arrays,
   strings, pointers to globals and into arrays, a function pointer, linked
   structs, a device-register address cast from an integer, a self pointer.
   x86-64: run under --c-static-data. xtensa: compiled --freestanding
   --emit-obj, linked by GNU ld, and the words read back
   (tools/check_xtensa_freestanding_obj.py). */
#ifndef PXX_NO_MAIN
#include <stdio.h>
#endif
struct dev { const char *name; int irq; int (*probe)(int); struct dev *next; };
int probe_a(int x) { return x * 3; }
int counter = 7;
int zero_one;
short tbl[4] = { 1, -2, 3, -4 };
const char *greet = "hello";
int *pc = &counter;
short *pt = &tbl[2];
unsigned long long big = 0x1122334455667788ULL;
struct dev devb = { "devb", 9, 0, 0 };
struct dev deva = { "deva", 5, probe_a, &devb };
int *pz = &zero_one;
volatile unsigned *uart = (volatile unsigned *)0x60000000;
void *self = (void *)&self;
char buf[4];
char *bp = buf + 2;
int ia[4];
int *ip = ia + 3;
struct lh { void *first; int n; };
struct lh lh0 = { ((void *)0), 4 };   /* LIST_HEAD_INITIALIZER, rump-pxx g19 */
int check(void) {
  int r = 0;
  if (counter == 7) r |= 1;
  if (tbl[3] == -4 && *pt == 3) r |= 2;
  if (greet[1] == 'e') r |= 4;
  if (*pc == 7) r |= 8;
  if (big == 0x1122334455667788ULL) r |= 16;
  if (deva.probe(2) == 6 && deva.next->irq == 9 && deva.next->name[3] == 'b') r |= 32;
  if (pz == &zero_one && *pz == 0) r |= 64;
  if ((unsigned long)uart == 0x60000000UL && self == (void *)&self) r |= 128;
  if (bp == &buf[2] && ip == &ia[3] && lh0.first == 0 && lh0.n == 4) r |= 256;
  return r;
}
#ifndef PXX_NO_MAIN
int main(void) { printf("%d\n", check()); return 0; }
#endif
