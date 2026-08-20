/* The RESULT side of the AnsiString rule: nothing on the C side keeps the
   returned value alive or releases it, so the routine is refused by name.
   The unit still imports -- strmod_pas_Plain is reachable in the sibling
   test -- and strmod's body BUILDS a managed string, which is what made this
   refusal unreachable until the C driver emitted the AnsiString runtime
   shims. bug-a-c-driver-omits-rtl-stubs-for-an-imported-pascal-unit */
#include <stdio.h>
#include "cpasunit/strmod.pas"

extern const char *strmod_pas_Tag(void);

int main(void) { printf("%s\n", strmod_pas_Tag()); return 0; }
