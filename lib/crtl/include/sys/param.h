/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/param.h> -- the BSD grab-bag. Macros only.
 *
 * Almost nobody includes this for its own content; they include it because
 * some other header did, or for MIN/MAX. busybox pulls it unconditionally
 * from include/libbb.h and the cat closure uses nothing from it. Its real job
 * here is to pull <limits.h>, <endian.h> and <signal.h> the way glibc's does,
 * so code that includes only <sys/param.h> still sees them.
 *
 * MIN/MAX are guarded. glibc defines them unconditionally and a project that
 * defined its own first gets a redefinition warning there; guarding is the
 * same behaviour for anything that compiles cleanly and quieter for the rest.
 * The values below are Linux's, which is the only platform this runtime
 * targets.
 */
#ifndef _CRTL_SYS_PARAM_H
#define _CRTL_SYS_PARAM_H

#include <limits.h>
#include <endian.h>
#include <signal.h>

#define MAXPATHLEN      4096
#define MAXSYMLINKS     20
#define MAXHOSTNAMELEN  64
#define NOFILE          256
#define NGROUPS         32
#define CANBSIZ         255
#define NCARGS          131072
#define DEV_BSIZE       512
#define NBBY            8

#ifndef MIN
#define MIN(a, b) (((a) < (b)) ? (a) : (b))
#endif
#ifndef MAX
#define MAX(a, b) (((a) > (b)) ? (a) : (b))
#endif

/* Integer helpers BSD callers expect. howmany rounds UP; roundup is howmany
   scaled back; powerof2 is true for zero as well, which is what the BSD
   original does and what callers that guard a mask rely on. */
#define howmany(x, y)   (((x) + ((y) - 1)) / (y))
#define roundup(x, y)   ((((x) + ((y) - 1)) / (y)) * (y))
#define powerof2(x)     ((((x) - 1) & (x)) == 0)

#endif
