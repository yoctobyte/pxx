/* SPDX-License-Identifier: MPL-2.0 */
/* C99 fenv — rounding-mode control only (no exception flags/traps).
   glibc x86 FE_* encoding; the compiler emits __pxx_fesetround/__pxx_fegetround
   as machine stubs (x86-64 flips MXCSR RC bits — pxx doubles are all-SSE;
   other targets accept-and-ignore, returning FE_TONEAREST). */
#ifndef _PXX_FENV_H
#define _PXX_FENV_H

#define FE_TONEAREST  0
#define FE_DOWNWARD   0x400
#define FE_UPWARD     0x800
#define FE_TOWARDZERO 0xc00

extern int __pxx_fesetround(int mode);
extern int __pxx_fegetround(void);

#define fesetround(m) __pxx_fesetround(m)
#define fegetround()  __pxx_fegetround()

#endif
