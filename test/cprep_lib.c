#include "cprep_defs.h"

#define CPREP_DISABLED 1
#undef CPREP_DISABLED

/* This function only becomes parsable source after preprocessing. */
#if defined(CPREP_DEFS_H) && CPREP_ENABLED == 1 && !defined(CPREP_DISABLED)
CPREP_API macro_add(int a, int b) {
    return CPREP_ADD(a, b);
}
#else
int macro_add(int a, int b) {
    return 0;
}
#endif
