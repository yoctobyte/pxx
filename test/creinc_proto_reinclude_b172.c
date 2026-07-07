/* Regression: a guardless header re-included by sibling .c files must not flip a
   locally-defined function back to external (dynamic import). Was zlib gz_error:
   pass-1 body-skip marked internal but the re-included prototype re-externalized
   it, so the pass-2 forward call became an undefined dynamic symbol. */
#include "creinc_b172/a.c"
#include "creinc_b172/b.c"
int main(void){ int x = 0; int r = b172_go(&x); if (r != 42) return 1; return 42; }
