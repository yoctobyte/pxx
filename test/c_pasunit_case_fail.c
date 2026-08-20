/* Case is significant: the mangled name carries the Pascal declaration's own
   spelling. `mymod_pas_twice` is not `mymod_pas_Twice`, and the case-insensitive
   global match this ticket exists to replace must not rescue it. */
#include <stdio.h>
#include "cpasunit/mymod.pas"

int main(void) { printf("%d\n", mymod_pas_twice(21)); return 0; }
