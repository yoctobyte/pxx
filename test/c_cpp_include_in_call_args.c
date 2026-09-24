/* SPDX-License-Identifier: 0BSD */
/* An #include inside an open call's argument list splices its tokens in
 * place. tcc's tccpp.c includes a generated string table as a call argument;
 * pxx used to lose the half-collected line and fail with "main function not
 * found". gcc and clang take every row. (Inside a MACRO invocation's arguments
 * gcc refuses the same thing, so that position is not a goal.) */
#include <stdio.h>

static int f(const char *s, int n) { return s[0] + n; }
static int g(const char *a, const char *b, int n) { return a[0] + b[0] + n; }
static const char *arr[] = {
#include "c_cpp_include_in_call_args.inc"
, "b" };

int main(void) {
    printf("call %d\n", f(
#include "c_cpp_include_in_call_args.inc"
    , -1));
    printf("under-if %d\n", f(
#if 1
#include "c_cpp_include_in_call_args.inc"
#endif
    , -2));
    printf("middle %d\n", g("b",
#include "c_cpp_include_in_call_args.inc"
    , -150));
    printf("dead-arm %d\n", f(
#if 0
#include "no_such_file.h"
#endif
#include "c_cpp_include_in_call_args.inc"
    , -3));
    printf("array %c%c\n", arr[0][0], arr[1][0]);
    return 0;
}
