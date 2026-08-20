/* A K&R declaration -- empty parameter list -- says nothing about the
   signature, so it cannot select an overload and it cannot be marshalled.
   Arity 0 matches only a genuinely parameterless routine, so this is refused
   by name rather than guessed at. */
#include <stdio.h>
#include "cpasunit/mymod.pas"

extern double mymod_pas_Max();

int main(void) { printf("%.2f\n", mymod_pas_Max(3.5, 9.25)); return 0; }
