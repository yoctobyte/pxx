/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <endian.h>.
 *
 * Every target this compiler emits for is LITTLE-endian (x86-64, i386,
 * aarch64, arm32, riscv32, xtensa), so __BYTE_ORDER is fixed here rather than
 * probed. If a big-endian target is ever added, this file is one of the places
 * that must change -- and it will fail loudly, because the htobe/betoh
 * families below are defined in terms of it.
 */
#ifndef _CRTL_ENDIAN_H
#define _CRTL_ENDIAN_H

#include <stdint.h>
#include <byteswap.h>

#define __LITTLE_ENDIAN 1234
#define __BIG_ENDIAN    4321
#define __PDP_ENDIAN    3412
#define __BYTE_ORDER    __LITTLE_ENDIAN
#define __FLOAT_WORD_ORDER __BYTE_ORDER

/* The unprefixed spellings, which <sys/param.h> and a lot of real code use. */
#define LITTLE_ENDIAN __LITTLE_ENDIAN
#define BIG_ENDIAN    __BIG_ENDIAN
#define PDP_ENDIAN    __PDP_ENDIAN
#define BYTE_ORDER    __BYTE_ORDER

#define htobe16(x) bswap_16(x)
#define htole16(x) ((uint16_t)(x))
#define be16toh(x) bswap_16(x)
#define le16toh(x) ((uint16_t)(x))

#define htobe32(x) bswap_32(x)
#define htole32(x) ((uint32_t)(x))
#define be32toh(x) bswap_32(x)
#define le32toh(x) ((uint32_t)(x))

#define htobe64(x) bswap_64(x)
#define htole64(x) ((uint64_t)(x))
#define be64toh(x) bswap_64(x)
#define le64toh(x) ((uint64_t)(x))

#endif
