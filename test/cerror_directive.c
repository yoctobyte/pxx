/* `#error` in a LIVE branch must stop the compile; in a NOT-TAKEN branch it must
   stay silent. This file pins the silent half — the half with the regression
   risk, since the corpora contain over a thousand `#error`s and essentially all
   of them sit behind guards that are not taken (unsupported platform, wrong
   compiler, missing feature macro). The failing half is a compile-time
   diagnostic and so cannot be asserted from inside a C program; it is gated as a
   {%FAIL} case in the Makefile alongside this test.
   bug-cfront-error-directive-silently-ignored */

#include <stdio.h>

#if 0
#error must never fire: #if 0
#endif

#ifdef DEFINITELY_NOT_DEFINED
#error must never fire: #ifdef of an undefined macro
#endif

#ifndef __STDC__
#error must never fire: #ifndef of a defined macro
#endif

#if defined(__x86_64__) && defined(__aarch64__)
#error must never fire: two arches at once
#endif

/* the shape real libraries use, and the one that made a Cython module compile
   with 5000 lines discarded: the guard's OTHER half holds the code */
#if 0
#error must never fire: unsupported configuration
#else
#define CONFIG_OK 1
#endif

/* nested: an #error inside a not-taken outer branch is unreachable even though
   its own inner condition is true */
#if 0
#  if 1
#    error must never fire: live inner test inside a dead outer branch
#  endif
#endif

/* an #elif chain where the #error arm is not the taken one */
#if 1
#define TOOK_FIRST 1
#elif 1
#error must never fire: not the taken elif arm
#else
#error must never fire: not the else arm
#endif

int main(void) {
#ifndef CONFIG_OK
    return 1;
#endif
#ifndef TOOK_FIRST
    return 2;
#endif
    return 42;
}
