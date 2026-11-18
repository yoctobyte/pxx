/* `static HANDLER h0, h1;` with HANDLER a function typedef: every name keeps
   `static`. Each split copy used to lose it after the first name, so h1 was an
   undefined external (expat's xmlrole.c, 41 handlers).
   bug-c-split-declarators-drop-static-after-the-first-name */
#include <stdio.h>
typedef int HANDLER(int *st, int tok);
static HANDLER h0, h1, h2;
static int (*cur)(int *, int);
static int h0(int *st, int tok) { *st += 1; cur = h1; return tok + 1; }
static int h1(int *st, int tok) { *st += 10; cur = h2; return tok * 2; }
static int h2(int *st, int tok) { *st += 100; cur = h0; return tok - 3; }
static int va, vb = 7, vc;
int main(void)
{
    int s = 0, t = 5, i;
    cur = h0;
    for (i = 0; i < 7; i++) t = cur(&s, t);
    va = s; vc = vb + 1;
    printf("%d %d %d %d\n", s, t, va, vc);
    return 0;
}
