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
 * TAKING jmp_buf BY VALUE IS SAFE HERE, which is the part worth explaining.
 * Our jmp_buf is a struct rather than the usual array typedef — deliberately,
 * because an array typedef loses its dimension in the C frontend and would be
 * sized as one long (see the header). A by-value parameter therefore COPIES the
 * 128-byte buffer. That is fine: longjmp only ever READS the saved stack
 * pointer, return address and callee-saved registers, so restoring from a copy
 * restores identical values. It is not fine to WRITE through such a copy, and
 * nothing here does.
 *
 * The names are parenthesised at the definition so the function-like macro does
 * not expand and eat the declarator. Callers writing the ordinary
 * `longjmp(env, val)` still get the macro, which skips the copy.
 */

#include <setjmp.h>

void (longjmp)(jmp_buf env, int val) { __pxx_longjmp(&env, val); }
void (_longjmp)(jmp_buf env, int val) { __pxx_longjmp(&env, val); }
void (siglongjmp)(jmp_buf env, int val) { __pxx_longjmp(&env, val); }
