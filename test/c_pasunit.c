/* feature-c-import-a-pascal-unit-under-a-mangled-name: a C file names a Pascal
   unit's routines explicitly, `<unit>_pas_<Identifier>`, case-exact.
   `#include "cpasunit/mymod.pas"` is NOT textual inclusion -- it becomes an
   import site, and the routines arrive as ordinary C declarations. The Max rows
   are the point of the prototype: ONE Pascal name, two overloads, and the C
   declaration's signature is what picks between them. */
#include <stdio.h>
#include "cpasunit/mymod.pas"

extern int mymod_pas_Max(int, int);

int main(void)
{
  printf("%d\n", mymod_pas_Twice(21));
  printf("%d\n", mymod_pas_Max(3, 7));
  return 0;
}
