/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_FLOAT_H
#define PXX_CRTL_FLOAT_H 1

/* IEEE-754 binary32 / binary64 limits — identical across all pxx targets
   (x86-64, i386, aarch64, arm32, riscv32); ABI-neutral pure macros. */

#define FLT_RADIX 2
#define FLT_ROUNDS 1        /* round to nearest */
#define FLT_EVAL_METHOD 0
#define DECIMAL_DIG 21

/* float (binary32) */
#define FLT_MANT_DIG 24
#define FLT_DIG 6
#define FLT_MIN_EXP (-125)
#define FLT_MIN_10_EXP (-37)
#define FLT_MAX_EXP 128
#define FLT_MAX_10_EXP 38
#define FLT_MAX 3.40282346638528859812e+38F
#define FLT_MIN 1.17549435082228750797e-38F
#define FLT_EPSILON 1.19209289550781250000e-7F
#define FLT_TRUE_MIN 1.40129846432481707092e-45F
#define FLT_DECIMAL_DIG 9
#define FLT_HAS_SUBNORM 1

/* double (binary64) */
#define DBL_MANT_DIG 53
#define DBL_DIG 15
#define DBL_MIN_EXP (-1021)
#define DBL_MIN_10_EXP (-307)
#define DBL_MAX_EXP 1024
#define DBL_MAX_10_EXP 308
#define DBL_MAX 1.79769313486231570815e+308
#define DBL_MIN 2.22507385850720138309e-308
#define DBL_EPSILON 2.22044604925031308085e-16
#define DBL_TRUE_MIN 4.94065645841246544177e-324
#define DBL_DECIMAL_DIG 17
#define DBL_HAS_SUBNORM 1

/* long double == double on pxx targets (no extended-precision type) */
#define LDBL_MANT_DIG 53
#define LDBL_DIG 15
#define LDBL_MIN_EXP (-1021)
#define LDBL_MIN_10_EXP (-307)
#define LDBL_MAX_EXP 1024
#define LDBL_MAX_10_EXP 308
#define LDBL_MAX 1.79769313486231570815e+308
#define LDBL_MIN 2.22507385850720138309e-308
#define LDBL_EPSILON 2.22044604925031308085e-16
#define LDBL_TRUE_MIN 4.94065645841246544177e-324
#define LDBL_DECIMAL_DIG 17
#define LDBL_HAS_SUBNORM 1

#endif
