/* SPDX-License-Identifier: Zlib */
/* Preprocessor and lexer shapes from libxkbcommon 1.13.1, written fresh.
   Compared with gcc's build of the same file (Makefile row c_xkbpp26).
     - #if: `>>` of a negative value is arithmetic, as gcc defines it
       (bug-c-if-right-shift-of-a-negative-value-is-logical)
     - a block comment spanning lines inside a #define, no backslashes in it
       (bug-c-a-multi-line-comment-ends-a-define-early)
     - u8"..." and u8'c' (feature-c-u8-string-literals)
     - #pragma once by three spellings of one path (feature-c-pragma-once)
     - sqrtl and friends (feature-crtl-long-double-math-aliases); not
       llroundl, whose llround crtl declares but does not define */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <math.h>

#include "c_xkb_preproc_inc/once.h"
#include "c_xkb_preproc_inc/sub/again.h"
#include "./c_xkb_preproc_inc/once.h"

#if (INT32_MIN >> 2) != -536870912 || (-8 >> 1) != -4 || (-1 >> 63) != -1
#error "#if right shift of a negative value is not arithmetic"
#endif
#if (-32) < (INT32_MIN >> 2) || 32 > (INT32_MAX >> 2)
#error "the xkbcommon state.c guard fires"
#endif

#define FOREACH(i, n) \
    /*
     * a comment over lines, inside the body,
     * with no backslash on these lines
     */ \
    for ((i) = 0; (i) < (n); (i)++)
#define TWO /* one
             two */ 2

int main(void)
{
    int i, s = 0;
    const char *lrm = u8"‎";
    const char *cat = u8"ab" "cd";
    char c = u8'z';

    FOREACH(i, 5) s += i;
    printf("foreach %d two %d line %d\n", s, TWO, __LINE__);
    printf("u8 %zu %02x%02x%02x %s %c\n", strlen(lrm), (unsigned char)lrm[0],
           (unsigned char)lrm[1], (unsigned char)lrm[2], cat, c);
    printf("once %d\n", once_value() + 1);
    printf("ldbl %lld %.3f %.3f %.3f %.1f\n", (long long)(sqrtl(2.0L) * 1000.0L + 0.5L),
           (double)fabsl(-1.5L), (double)floorl(2.7L), (double)powl(2.0L, 10.0L),
           (double)fmodl(7.0L, 3.0L));
    return 0;
}
