/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_ASSERT_H
#define PXX_CRTL_ASSERT_H 1

#ifdef NDEBUG
#define assert(expr) ((void)0)
#else
void __pxx_assert_fail(const char *expr, const char *file, int line);
#define assert(expr) ((expr) ? (void)0 : __pxx_assert_fail(#expr, __FILE__, __LINE__))
#endif

#endif
