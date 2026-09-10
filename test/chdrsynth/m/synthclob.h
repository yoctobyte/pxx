/* THE REGRESSION FIXTURE FOR
 * bug-c-an-unresolvable-synthesised-soname-still-reaches-dt-needed.
 *
 * Reached by `uses synthclob`, so the compiler invents `libsynthclob.so` from
 * this file's NAME and hangs it on every external the include chain declares --
 * libc's included. `RegisterExternal` used to repair that, and the repair was
 * then overwritten. Three writes, in this order, for `memcmp`:
 *
 *   1. cparser.inc's prototype arm, from <string.h> below -> libsynthclob.so
 *   2. RegisterExternal, when sc_cmp's BODY calls memcmp mid-parse: this
 *      directory is named `m`, ld.so.cache answers libm.so.6, libm does not
 *      export memcmp and libc does -> libc.so.6, correctly
 *   3. the re-declaration at the bottom of this file -> libsynthclob.so AGAIN
 *
 * and step 3 is why the guard could be present, correct, and useless. The
 * binary linked clean and died with `cannot open shared object file:
 * libsynthclob.so`. Found on `import "/usr/include/SDL2/SDL.h"`, where glibc's
 * own headers supply all three steps; this file supplies them explicitly so the
 * row needs nothing installed but glibc.
 *
 * EVERY LINE HERE IS LOAD-BEARING, and each was ablated against the PRE-FIX
 * compiler on 2026-09-10 rather than argued:
 *
 *   - rename the `m` directory -> no library answers, so step 2 never runs and
 *     the build is REFUSED at compile time. Loud, and not this bug.
 *   - drop sc_cmp's body -> nothing registers the external while the header is
 *     still being parsed, so the repair lands after the last write. Correct
 *     binary, libc.so.6.
 *   - drop the re-declaration -> nothing overwrites the repair. Correct binary,
 *     libc.so.6.
 *
 * So the row is not merely reproducing a bug, it is reproducing the only shape
 * that reaches it -- and none of the three variants would have caught the
 * regression this file exists to catch. */
#include <string.h>

/* Registers memcmp as an external DURING the header parse -- this is what puts
   the repair before the last write rather than after it. */
static __inline__ int sc_cmp(const void *a, const void *b, unsigned long n)
{ return memcmp(a, b, n); }

/* The overwrite. A re-declaration is ordinary in a real header chain; it took
   the repair with it. */
extern int memcmp(const void *a, const void *b, unsigned long n);
