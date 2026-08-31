/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <byteswap.h> -- the GNU byte-order primitives.
 *
 * Macros, not functions, so they constant-fold and so no call crosses a
 * translation unit for three instructions' worth of work. The operand is
 * parenthesised and used once per subexpression, which is why `bswap_16(*p++)`
 * would be wrong here -- but that is glibc's contract too, and every caller in
 * the corpus passes a plain value.
 */
#ifndef _CRTL_BYTESWAP_H
#define _CRTL_BYTESWAP_H

#include <stdint.h>

#define bswap_16(x) ((uint16_t)((((uint16_t)(x) & 0x00ffU) << 8) | \
                                (((uint16_t)(x) & 0xff00U) >> 8)))

#define bswap_32(x) ((uint32_t)((((uint32_t)(x) & 0x000000ffUL) << 24) | \
                                (((uint32_t)(x) & 0x0000ff00UL) <<  8) | \
                                (((uint32_t)(x) & 0x00ff0000UL) >>  8) | \
                                (((uint32_t)(x) & 0xff000000UL) >> 24)))

#define bswap_64(x) ((uint64_t)((((uint64_t)(x) & 0x00000000000000ffULL) << 56) | \
                                (((uint64_t)(x) & 0x000000000000ff00ULL) << 40) | \
                                (((uint64_t)(x) & 0x0000000000ff0000ULL) << 24) | \
                                (((uint64_t)(x) & 0x00000000ff000000ULL) <<  8) | \
                                (((uint64_t)(x) & 0x000000ff00000000ULL) >>  8) | \
                                (((uint64_t)(x) & 0x0000ff0000000000ULL) >> 24) | \
                                (((uint64_t)(x) & 0x00ff000000000000ULL) >> 40) | \
                                (((uint64_t)(x) & 0xff00000000000000ULL) >> 56)))

#endif
