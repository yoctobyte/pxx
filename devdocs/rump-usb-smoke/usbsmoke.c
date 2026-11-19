/* rump_init with the USB components linked in: autoconf attaches what the
   PCI stub offers (xhcistub.c). The console lines are the result. */
#include <stdio.h>
int rump_init(void);
int main(void)
{
  int rv = rump_init();
  printf("usbsmoke: rump_init rv %d\n", rv);
  return rv != 0;
}
