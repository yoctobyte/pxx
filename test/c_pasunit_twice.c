/* The SAME unit file included twice is not a collision -- it is the ordinary
   idempotent include, and it stays allowed. Only two different files claiming
   one unit name are refused (c_pasunit_collide_fail.c) -- and the comparison is on the RESOLVED path, so
   the third spelling below, differing only by a './', is the same file too. */
#include <stdio.h>
#include "cpasunit/mymod.pas"
#include "cpasunit/mymod.pas"
#include "./cpasunit/mymod.pas"

int main(void) { printf("%d\n", mymod_pas_Twice(21)); return 0; }
