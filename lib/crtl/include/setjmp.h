/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SETJMP_H
#define PXX_CRTL_SETJMP_H 1

/* jmp_buf is a STRUCT (not a typedef'd array): an array typedef `long jmp_buf[16]`
   loses its dimension in the C frontend and is sized as one long (8 bytes), so a
   struct field of it would underflow the frame. A struct wrapping the array is
   sized correctly (128 bytes). The macros pass &env (the struct's address) to the
   intrinsics, which expect the buffer address. */
typedef struct { long __jb[16]; } jmp_buf;

/* sigjmp_buf: the same register buffer FIRST (so &env is still the address
   __pxx_setjmp wants), then whether sigsetjmp saved the signal mask and the mask
   itself -- sigset_t's layout, spelled out so this header need not include
   <signal.h>. sigsetjmp(env, savemask) records the mask (or the flag 0) BEFORE
   the setjmp, in the caller's own expression, because setjmp has to run in the
   caller's frame; siglongjmp puts the mask back before jumping. That is the
   difference that matters to a longjmp out of a signal handler: without it the
   signal stays blocked. toybox keeps a `sigjmp_buf *rebound` in every applet's
   context. */
typedef struct { long __jb[16]; long __saved; unsigned long __mask[16]; } sigjmp_buf;
extern void __pxx_sigjmp_save(sigjmp_buf *env, int savemask);
extern void __pxx_sigjmp_restore(sigjmp_buf *env);

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
extern void siglongjmp(sigjmp_buf env, int val);

#define setjmp(env)         __pxx_setjmp(&(env))
#define _setjmp(env)        __pxx_setjmp(&(env))
#define sigsetjmp(env, s)   (__pxx_sigjmp_save(&(env), (s)), __pxx_setjmp(&(env)))
#define longjmp(env, val)   __pxx_longjmp(&(env), val)
#define _longjmp(env, val)  __pxx_longjmp(&(env), val)
#define siglongjmp(env, v)  (__pxx_sigjmp_restore(&(env)), __pxx_longjmp(&(env), v))

#endif
