/* A Pascal unit #included by a C program has its `initialization` section
   run before main's body, as a Pascal program runs it before its own. It
   never ran: GetReady() returned 0 and the WriteLn printed nothing.
   bug-c-a-pascal-units-initialization-never-runs-under-a-c-main */
#include <stdio.h>
#include "c_pascal_unit_init_unit.pas"

int main(void) {
  printf("ready=%d\n", GetReady());
  return 0;
}
