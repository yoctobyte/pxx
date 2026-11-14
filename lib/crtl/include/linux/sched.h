/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/sched.h> -- the clone(2) flags.
 *
 * Written for pxx from the kernel's documented ABI (the numbers are the ABI,
 * checked against a gcc build over the system header on x86-64 and i386);
 * only what userland tools reach. Without it a native x86-64 build silently
 * took the HOST's copy and every cross target failed to find one.
 * Found building toybox (feature-c-toybox-builds-with-pxx).
 */
#ifndef PXX_CRTL_LINUX_SCHED_H
#define PXX_CRTL_LINUX_SCHED_H 1

#include <sched.h>   /* which already spells the CLONE_* set */

#endif
