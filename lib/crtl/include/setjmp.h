/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SETJMP_H
#define PXX_CRTL_SETJMP_H 1

/* jmp_buf is glibc's shape: an ARRAY of one struct. It decays to the buffer's
   address wherever it is passed, so `setjmp` called through a function pointer,
   or a function taking a `jmp_buf env` parameter, writes the caller's buffer.
   It was a plain struct until 2026-11-22, a workaround for an array typedef
   that lost its dimension (fixed since); passed by value that was a COPY, and
   a setjmp through micropython's function table filled the copy -- the later
   longjmp restored zeros. The macros pass the decayed array. */
struct __jmp_buf_tag { long __jb[16]; };
typedef struct __jmp_buf_tag jmp_buf[1];

/* sigjmp_buf: the same register buffer FIRST (so the decayed env is still the
   address __pxx_setjmp wants), then whether sigsetjmp saved the signal mask and the mask
   itself -- sigset_t's layout, spelled out so this header need not include
   <signal.h>. sigsetjmp(env, savemask) records the mask (or the flag 0) BEFORE
   the setjmp, in the caller's own expression, because setjmp has to run in the
   caller's frame; siglongjmp puts the mask back before jumping. That is the
   difference that matters to a longjmp out of a signal handler: without it the
   signal stays blocked. toybox keeps a `sigjmp_buf *rebound` in every applet's
   context. */
struct __sigjmp_buf_tag { long __jb[16]; long __saved; unsigned long __mask[16]; };
typedef struct __sigjmp_buf_tag sigjmp_buf[1];
extern void __pxx_sigjmp_save(struct __sigjmp_buf_tag *env, int savemask);
extern void __pxx_sigjmp_restore(struct __sigjmp_buf_tag *env);

extern int  __pxx_setjmp(void *env);
extern void __pxx_longjmp(void *env, int val);

/* Real FUNCTIONS as well as the macros below. C 7.13: setjmp may be a macro,
   longjmp SHALL be an external function — and code takes its address (tcc's
   tcc_setjmp macro passes `longjmp` as a function pointer). A function-like
   macro does not expand unless the name is followed by `(`, so these
   declarations are what a bare `longjmp` resolves to, while an ordinary
   longjmp(env, val) call still takes the macro below. Bodies in src/setjmp.c. */
extern void longjmp(jmp_buf env, int val);
/* and setjmp, whose address code takes too (micropython's nativeglue.c); the
   compiler emits its body beside __pxx_setjmp's (EmitCSetjmpStubs) */
extern int  setjmp(jmp_buf env);
extern void _longjmp(jmp_buf env, int val);
extern void siglongjmp(sigjmp_buf env, int val);

#define setjmp(env)         __pxx_setjmp(env)
#define _setjmp(env)        __pxx_setjmp(env)
#define sigsetjmp(env, s)   (__pxx_sigjmp_save((env), (s)), __pxx_setjmp(env))
#define longjmp(env, val)   __pxx_longjmp((env), val)
#define _longjmp(env, val)  __pxx_longjmp((env), val)
#define siglongjmp(env, v)  (__pxx_sigjmp_restore(env), __pxx_longjmp((env), v))

#endif
