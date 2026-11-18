/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_ASSERT_H
#define PXX_CRTL_ASSERT_H 1

#ifdef NDEBUG
#define assert(expr) ((void)0)
#elif defined(__PXX_SYSTEM_ASSERT__)
/* --system-libs: the libc's own sink (glibc/musl ABI); crtl's assert.c is
   not pulled on that path, and no libc exports __pxx_assert_fail. */
void __assert_fail(const char *expr, const char *file, unsigned int line,
                   const char *func);
#define assert(expr) ((expr) ? (void)0 : __assert_fail(#expr, __FILE__, __LINE__, __func__))
#else
void __pxx_assert_fail(const char *expr, const char *file, int line);
#define assert(expr) ((expr) ? (void)0 : __pxx_assert_fail(#expr, __FILE__, __LINE__))
#endif

#endif
