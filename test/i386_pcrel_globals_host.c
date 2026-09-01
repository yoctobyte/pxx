/* gcc -m32 side of test/i386_pcrel_globals.c -- see that file's header for why
   the VALUE is asserted rather than the link. The expected number is written
   out as the same expression the subject computes, so a change to either side
   has to be made in both. */
#include <stdio.h>

extern int pic_probe(int k);

int main(void)
{
  int r = pic_probe(1000);
  int want = 1000 + 0x11223344 + (-70000) + 200 + (-100) + 60000 + (-30000) + 110;
  if (r >= 101 && r <= 112) { printf("FAIL: subject row %d\n", r); return 1; }
  if (r != want) { printf("FAIL: pic_probe=%d want=%d\n", r, want); return 1; }
  printf("PCREL GLOBALS OK\n");
  return 0;
}
