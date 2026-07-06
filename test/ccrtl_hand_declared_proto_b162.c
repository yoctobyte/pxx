/* Regression: a hand-declared libc prototype (no #include) must still bind to
   the crtl implementation, not silently no-op. Returns 42. */
extern unsigned long strlen(const char *);
extern int strcmp(const char *, const char *);
extern void *memset(void *, int, unsigned long);
int main(void) {
    char buf[8];
    if (strlen("hello") != 5) return 1;
    if (strcmp("ab", "ab") != 0) return 2;
    memset(buf, 'x', 4);
    if (buf[0] != 'x' || buf[3] != 'x') return 3;
    return 42;
}
