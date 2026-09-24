/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <features.h> -- glibc's feature-test header, and here a
 * DELIBERATELY EMPTY one as far as libc identity goes.
 *
 * IT EXISTS SO THAT __GLIBC__ STAYS UNDEFINED. Programs include this header to
 * ask "which libc is this?", and the whole answer crtl has to give is "not
 * glibc". busybox's libbb/makedev.c is exactly that shape: it includes
 * <features.h>, then `#ifdef __GLIBC__' selects a wrapper around glibc's
 * "horrendously large inline" makedev. Reaching the HOST's <features.h>
 * instead would define __GLIBC__ and __GLIBC_PREREQ and send a crtl-linked
 * program down glibc's arm -- a header that answers, correctly, about the
 * wrong libc.
 *
 * So there is nothing to define here, and nothing SHOULD be: every macro this
 * file could carry is one crtl would then have to keep true. The value is the
 * existence.
 *
 * Found attempting busybox on i386, where there is no host <features.h> to
 * fall back on. feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_FEATURES_H
#define _CRTL_FEATURES_H

/* No libc facts here -- see the comment above before adding any. The one
 * include is declaration glue, as in glibc's own <features.h>: a host header
 * crtl does not ship (semaphore.h, ...) opens with __BEGIN_DECLS and relies on
 * this file to have defined it. crtl's <sys/cdefs.h> defines only attribute
 * and C++-bracket spellings, none of which says which libc this is. */
#include <sys/cdefs.h>

#endif
