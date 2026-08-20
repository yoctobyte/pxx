/* No prototype for an OVERLOADED Pascal routine: there is nothing to select
   with, so the call is refused and the refusal names the fix (declare the
   signature you mean) rather than picking an overload silently. */
#include <stdio.h>
#include "cpasunit/mymod.pas"

int main(void) { printf("%d\n", mymod_pas_Max(3, 7)); return 0; }
