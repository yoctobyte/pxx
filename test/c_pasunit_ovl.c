/* ONE Pascal name, two overloads: the C DECLARATION's signature is what picks
   between them. This file's prototype is the Double one; c_pasunit.c declares
   the Integer one for the same mangled name and gets the Integer body. */
#include <stdio.h>
#include "cpasunit/mymod.pas"

extern double mymod_pas_Max(double, double);

int main(void) { printf("%.2f\n", mymod_pas_Max(3.5, 9.25)); return 0; }
