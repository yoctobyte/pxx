/* Regression: a string literal in a binary op is a char* pointer value, so
   `"abc" == (void*)0` compares pointers (not content, which derefs NULL and
   SIGSEGV'd). Returns 42. */
int main(void) {
    if ("abc" == (void *)0) return 1;      /* non-null literal != NULL */
    if (!("abc" != (void *)0)) return 2;
    const char *p = "hello";
    if (p != "hello" ? 0 : 0) return 3;    /* pointer compare, no deref/crash */
    return 42;
}
