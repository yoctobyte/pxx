/* SPDX-License-Identifier: 0BSD */
/* Host headers crtl does not ship open with __BEGIN_DECLS and decorate their
 * prototypes with __THROW / __nonnull / __REDIRECT, relying on <features.h>
 * to have pulled in <sys/cdefs.h>. crtl's <features.h> is empty of libc facts
 * (so __GLIBC__ stays undefined) but includes crtl's glue <sys/cdefs.h>.
 * Before that, every one of these was refused with "stray token at top level
 * (not a declaration): '__BEGIN_DECLS'" -- the first wall of the tcc build,
 * whose tcc.h includes <semaphore.h>. */
#include <semaphore.h>
#include <search.h>
#include <spawn.h>
#include <ftw.h>
#include <langinfo.h>
#include <stdio.h>

#ifdef __GLIBC__
#error "__GLIBC__ must stay undefined under crtl: see lib/crtl/include/features.h"
#endif

int main(void) {
    printf("host headers parsed\n");
    return 0;
}
