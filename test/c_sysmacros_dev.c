/* crtl's <sys/sysmacros.h> against glibc's, row for row.

   Linux's dev_t is the "new" split encoding -- 12-bit major and 20-bit minor,
   each stored in TWO pieces -- so major()/minor() each OR two fields. The rows
   that earn this test are the ones a naive `(dev >> 8) & 0xfff` still passes
   nowhere: minors above 255 (loop7 vs loop300), majors above 4095, and the
   round trip through makedev() for both. */
#include <stdio.h>
#include <sys/types.h>
#include <sys/sysmacros.h>

static void row(unsigned maj, unsigned min)
{
  dev_t d = makedev(maj, min);
  printf("makedev(%u,%u)=%llu major=%u minor=%u roundtrip=%d\n",
         maj, min, (unsigned long long)d, major(d), minor(d),
         major(d) == maj && minor(d) == min);
}

int main(void)
{
  row(0, 0);
  row(1, 3);         /* /dev/null */
  row(8, 0);         /* /dev/sda  */
  row(7, 255);       /* last minor that fits the low field */
  row(7, 256);       /* first minor that needs the high field */
  row(7, 300);       /* loop300 */
  row(136, 1048575); /* /dev/pts, largest 20-bit minor */
  row(4095, 1);      /* last major that fits the low field */
  row(4096, 1);      /* first major that needs the high field */
  row(1048575, 1048575);
  printf("literal: major(0x1234)=%u minor(0x1234)=%u\n",
         major((dev_t)0x1234), minor((dev_t)0x1234));
  return 0;
}
