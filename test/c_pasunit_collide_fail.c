/* Two DIFFERENT files both declaring `unit mymod`. A unit's identity here is
   its NAME, not its path, so the second import is a silent no-op in the loader
   -- mymod_pas_Twice would answer 42 where the author asked for 63. Refused by
   name at compile time rather than answering the wrong file's routine. */
#include <stdio.h>
#include "cpasunit/mymod.pas"
#include "cpasunit2/mymod.pas"

int main(void) { printf("%d\n", mymod_pas_Twice(21)); return 0; }
