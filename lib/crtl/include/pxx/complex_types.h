/* SPDX-License-Identifier: Zlib */
/*
 * The LAYOUT of C99's complex types, which cfront maps `_Complex T` onto
 * (`_Complex double` -> struct __pxx_complex_double, either word order;
 * gcc's `__complex__` too). Pulled in by the preprocessor the first time an
 * expanded line mentions _Complex, as stdarg.h is for __builtin_va_list.
 *
 * Layout only, on purpose: C11 6.2.5p13 makes a complex type "the same
 * representation and alignment requirements as an array type containing
 * exactly two elements of the corresponding real type", and the SysV x86-64
 * ABI passes _Complex float / _Complex double exactly as these structs (one
 * and two SSE eightbytes). sizeof, alignment, members, copies, passing and
 * returning are therefore right. ARITHMETIC is not modelled: cfront refuses
 * it by name rather than computing a struct. _Complex long double inherits
 * pxx's 8-byte long double (bug: long double is 8 bytes in pxx).
 * libffi's src/types.c needs sizeof/offsetof of each (ffi_type_complex_*).
 * feature-c-complex-types-as-layout
 */
#ifndef PXX_CRTL_COMPLEX_TYPES_H
#define PXX_CRTL_COMPLEX_TYPES_H 1
struct __pxx_complex_float   { float __re, __im; };
struct __pxx_complex_double  { double __re, __im; };
struct __pxx_complex_ldouble { long double __re, __im; };
#endif
