/* Naming a routine whose signature carries an AnsiString is refused by name.
   The unit itself imports fine -- strmod_pas_Plain is reachable -- so what is
   refused is the one routine, not the file. */
#include <stdio.h>
#include "cpasunit/strmod.pas"

extern int strmod_pas_Greet(const char *);

int main(void) { printf("%d\n", strmod_pas_Greet("hi")); return 0; }
