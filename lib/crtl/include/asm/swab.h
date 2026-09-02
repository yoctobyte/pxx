/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <asm/swab.h> -- DELIBERATELY EMPTY OF __arch_swab*.
 *
 * This is not a stub and it is not a reimplementation. <linux/swab.h> is a
 * kernel UAPI header that a program legitimately takes from the host (it is the
 * KERNEL's ABI, not the libc's), and it is written to work either way:
 *
 *     #include <asm/swab.h>
 *     ...
 *     #if defined(__arch_swab32)
 *         return __arch_swab32(val);
 *     #else
 *         return ___constant_swab32(val);   -- portable C, right there
 *     #endif
 *
 * The host's x86 <asm/swab.h> defines __arch_swab32 as
 * `__asm__("bswapl %0" : "=r" (val) : "0" (val))', and pxx's C frontend refuses
 * a non-empty inline-asm template rather than silently dropping the
 * instructions. Measured 2026-09-02: that one header stopped busybox's
 * networking/udhcp/dhcpc.c, reached through <linux/filter.h> and
 * <linux/if_packet.h>, in a build where the other 399 translation units were
 * fine with the host's kernel headers.
 *
 * Shadowing it with a file that defines NOTHING makes linux/swab.h take its own
 * portable branch, which computes the identical value. So the byte swap is
 * still the kernel header's, not ours -- there is no second implementation here
 * to drift, and nothing to re-check when pxx grows real inline asm
 * (feature-c-gnu-inline-asm-with-a-non-empty-template). At that point this file
 * can simply be deleted and the host's arch version resumes.
 *
 * Scope: byte swapping only. Nothing else in <asm/> is shadowed, and a program
 * reaching for a genuinely arch-specific asm header still gets the host's and
 * still gets a loud refusal, which is the honest outcome.
 */
#ifndef _CRTL_ASM_SWAB_H
#define _CRTL_ASM_SWAB_H

/* Intentionally no __arch_swab16 / __arch_swab32 / __arch_swab64, and no
   __arch_swab*p / __arch_swab*s. Every one of those names is TESTED with
   #ifdef by <linux/swab.h>; defining any of them here would replace a working
   portable branch with a copy of it. */

#endif
