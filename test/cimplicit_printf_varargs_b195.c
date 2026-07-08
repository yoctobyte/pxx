/* b195: IMPLICIT printf (no include, no prototype — C89 style) must bind the
   real variadic crtl printf, not an implicit non-variadic int() that drops
   the varargs and prints the format string literally ("x=%d"). The undeclared
   -call scan in CPullCrtlForPrototypes pulls <stdio.h> when a call names a
   known crtl function with no registered proc. Also retires the literal-only
   ParseCPrintfAST stub (early bring-up relic). */

int strcmp(const char *, const char *);

int buf_check(char *p) {
    /* sprintf is stdio too — same implicit pull, different function */
    sprintf(p, "n=%d s=%s", 7, "seven");
    return strcmp(p, "n=7 s=seven") == 0;
}

int main(void) {
    char buf[64];
    int x = 42;
    printf("x=%d y=%s\n", x, "ok");      /* formats, not literal */
    if (!buf_check(buf)) return 1;
    return 42;
}
