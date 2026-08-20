/* C has ONE declaration per name, so a single .c file cannot name two overloads
   of one Pascal routine. Refused by name; without it the second declaration
   fell through to the cross-namespace rung and the call returned 0. */
#include <stdio.h>
#include "cpasunit/mymod.pas"

extern int mymod_pas_Max(int, int);
extern double mymod_pas_Max(double, double);

int main(void) { printf("%d\n", mymod_pas_Max(3, 7)); return 0; }
