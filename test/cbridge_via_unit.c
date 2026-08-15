/* Pulled in by test/unit_c_bridge.pas, which is itself only reached through a
   Pascal program's uses clause. Two things are under test at once:
     - malloc/free lower onto pxxcio's __pxx_malloc/__pxx_free, which nothing in
       the Pascal source could have named, so the C-program path's ambient pull
       has to happen on this path too (bug-pascal-uses-is-transitive);
     - the header/TU content must survive that pull. The first cut of it left
       UnitContent (a global) clobbered by the nested unit load, so every
       declaration below silently vanished and the caller reported them as
       undefined variables. */
#include <stdlib.h>

int cbridge_twice(int x)
{
  int *p = (int *)malloc(sizeof(int));
  int r;
  *p = x + x;
  r = *p;
  free(p);
  return r;
}
