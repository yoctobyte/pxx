/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/cdefs.h> -- the declaration glue glibc's headers are written
 * in, with every decoration spelled as nothing.
 *
 * WHY THIS HOLDS MORE THAN crtl'S OWN HEADERS USE. A header crtl does not ship
 * (semaphore.h, sched.h, ...) is found in /usr/include, and glibc's headers
 * expect <features.h> to have pulled this file in: they open with
 * __BEGIN_DECLS and decorate every prototype with __THROW / __nonnull(...) /
 * __wur. crtl's <features.h> is deliberately empty of LIBC facts (so
 * __GLIBC__ stays undefined -- see that file), but it includes this one,
 * exactly as glibc's does, so those headers parse again. Everything here is
 * an attribute or a C++ bracket with no meaning to a C compiler that ignores
 * attributes; nothing here says which libc this is.
 *
 * __REDIRECT drops glibc's asm-label alias and declares the plain name: the
 * call then binds to crtl's function of that name, which is the one that
 * exists. The census for this file (2026-09-25, x86-64): 36 host headers
 * refused at __BEGIN_DECLS before, see the LOGBOOK line.
 */
#ifndef PXX_CRTL_SYS_CDEFS_H
#define PXX_CRTL_SYS_CDEFS_H 1

#define __BEGIN_DECLS
#define __END_DECLS
#define __restrict
#define __restrict__
#define __const const
#define __inline

#ifndef __THROW
#define __THROW
#endif
#ifndef __THROWNL
#define __THROWNL
#endif
#ifndef __NTH
#define __NTH(fct) fct
#endif
#ifndef __NTHNL
#define __NTHNL(fct) fct
#endif
#ifndef __LEAF
#define __LEAF
#endif
#ifndef __LEAF_ATTR
#define __LEAF_ATTR
#endif
#ifndef __wur
#define __wur
#endif
#ifndef __nonnull
#define __nonnull(params)
#endif
#ifndef __returns_nonnull
#define __returns_nonnull
#endif
#ifndef __attribute_const__
#define __attribute_const__
#endif
#ifndef __attribute_pure__
#define __attribute_pure__
#endif
#ifndef __attribute_malloc__
#define __attribute_malloc__
#endif
#ifndef __attribute_deprecated__
#define __attribute_deprecated__
#endif
#ifndef __attribute_warn_unused_result__
#define __attribute_warn_unused_result__
#endif
#ifndef __attribute_used__
#define __attribute_used__
#endif
#ifndef __attribute_noinline__
#define __attribute_noinline__
#endif
#ifndef __attribute_maybe_unused__
#define __attribute_maybe_unused__
#endif
#ifndef __attribute_format_arg__
#define __attribute_format_arg__(x)
#endif
#ifndef __attribute_format_strfmon__
#define __attribute_format_strfmon__(a, b)
#endif
#ifndef __attr_access
#define __attr_access(x)
#endif
#ifndef __attr_access_none
#define __attr_access_none(argno)
#endif
#ifndef __attr_dealloc
#define __attr_dealloc(dealloc, argno)
#endif
#ifndef __attr_dealloc_free
#define __attr_dealloc_free
#endif
#ifndef __fortify_function
#define __fortify_function
#endif
#ifndef __errordecl
#define __errordecl(name, msg) extern void name (void)
#endif
#ifndef __warndecl
#define __warndecl(name, msg) extern void name (void)
#endif
#ifndef __REDIRECT
#define __REDIRECT(name, proto, alias) name proto
#endif
#ifndef __REDIRECT_NTH
#define __REDIRECT_NTH(name, proto, alias) name proto
#endif
#ifndef __REDIRECT_NTHNL
#define __REDIRECT_NTHNL(name, proto, alias) name proto
#endif
#ifndef __glibc_has_builtin
#define __glibc_has_builtin(name) 0
#endif
#ifndef __glibc_has_attribute
#define __glibc_has_attribute(attr) 0
#endif
#ifndef __glibc_likely
#define __glibc_likely(cond) (cond)
#endif
#ifndef __glibc_unlikely
#define __glibc_unlikely(cond) (cond)
#endif
#ifndef __always_inline
#define __always_inline inline
#endif
#ifndef __restrict_arr
#define __restrict_arr
#endif
#ifndef __flexarr
#define __flexarr []
#endif
#ifndef __P
#define __P(args) args
#endif
#ifndef __PMT
#define __PMT(args) args
#endif
#ifndef __CONCAT
#define __CONCAT(x, y) x ## y
#endif
#ifndef __STRING
#define __STRING(x) #x
#endif
#ifndef __ptr_t
#define __ptr_t void *
#endif

#endif
