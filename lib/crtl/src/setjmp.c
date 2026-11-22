/* SPDX-License-Identifier: Zlib */
/*
 * Real `longjmp` / `_longjmp` / `siglongjmp` FUNCTIONS, alongside the macros in
 * <setjmp.h>.
 *
 * C 7.13 is explicit: `setjmp` may be a macro, but `longjmp` shall be an
 * external function. We had macros only, and a function-like macro does not
 * expand when its name is not followed by `(` — so a bare `longjmp` used as a
 * VALUE was an undeclared identifier. Real code does that: tcc's
 *
 *     #define tcc_setjmp(s1,jb,f) setjmp(_tcc_setjmp(s1, jb, f, longjmp))
 *
 * passes longjmp as a function pointer, and libtcc.c stopped there
 * (feature-crtl-implement-libc-assumptions, corpus step 3).
 *
 * jmp_buf is glibc's array of one struct (see the header), so `env` here is
 * the caller's buffer itself, not a copy.
 *
 * The names are parenthesised at the definition so the function-like macro does
 * not expand and eat the declarator. Callers writing the ordinary
 * `longjmp(env, val)` still get the macro, which skips the copy.
 */

#include <setjmp.h>
#include <signal.h>

void (longjmp)(jmp_buf env, int val) { __pxx_longjmp(env, val); }
void (_longjmp)(jmp_buf env, int val) { __pxx_longjmp(env, val); }
void (siglongjmp)(sigjmp_buf env, int val) { __pxx_sigjmp_restore(env); __pxx_longjmp(env, val); }

/* sigsetjmp's mask half (see <setjmp.h>). */
void __pxx_sigjmp_save(struct __sigjmp_buf_tag *env, int savemask)
{
  env->__saved = savemask != 0;
  if (savemask) sigprocmask(SIG_BLOCK, 0, (sigset_t *)env->__mask);
}

void __pxx_sigjmp_restore(struct __sigjmp_buf_tag *env)
{
  if (env->__saved) sigprocmask(SIG_SETMASK, (sigset_t *)env->__mask, 0);
}
