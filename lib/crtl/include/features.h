/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <features.h> -- glibc's feature-test header, and here a
 * DELIBERATELY EMPTY one.
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

/* intentionally empty -- see the comment above before adding anything */

#endif
