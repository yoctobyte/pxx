/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SETJMP_H
#define PXX_CRTL_SETJMP_H 1

/* jmp_buf is a STRUCT (not a typedef'd array): an array typedef `long jmp_buf[16]`
   loses its dimension in the C frontend and is sized as one long (8 bytes), so a
   struct field of it would underflow the frame. A struct wrapping the array is
   sized correctly (128 bytes). The macros pass &env (the struct's address) to the
   intrinsics, which expect the buffer address. */
typedef struct { long __jb[16]; } jmp_buf;

extern int  __pxx_setjmp(void *env);
extern void __pxx_longjmp(void *env, int val);

/* Real FUNCTIONS as well as the macros below. C 7.13: setjmp may be a macro,
   longjmp SHALL be an external function — and code takes its address (tcc's
   tcc_setjmp macro passes `longjmp` as a function pointer). A function-like
   macro does not expand unless the name is followed by `(`, so these
   declarations are what a bare `longjmp` resolves to, while an ordinary
   longjmp(env, val) call still takes the macro below. Bodies in src/setjmp.c. */
extern void longjmp(jmp_buf env, int val);
extern void _longjmp(jmp_buf env, int val);
extern void siglongjmp(jmp_buf env, int val);

#define setjmp(env)         __pxx_setjmp(&(env))
#define _setjmp(env)        __pxx_setjmp(&(env))
#define sigsetjmp(env, s)   __pxx_setjmp(&(env))
#define longjmp(env, val)   __pxx_longjmp(&(env), val)
#define _longjmp(env, val)  __pxx_longjmp(&(env), val)
#define siglongjmp(env, v)  __pxx_longjmp(&(env), v)

#endif
