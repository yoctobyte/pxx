/* K&R (old-style) function definitions: an identifier list, then the
   parameter declarations, then the body. Old X server code (TinyX's mi/,
   dix/, Xext/) is written this way. An undeclared parameter is int.
   feature-c-k-and-r-function-definitions */
#include <stdio.h>

typedef struct { int x, y; } Pt, *PtPtr;

static int add(a, b) int a, b; { return a + b; }

static long mix(p, s, n, fn, q)
    char *s;
    PtPtr p;
    register int n;
    int (*fn)();
    const Pt *q;
{
    return p->x * 1000 + (s[0] == 'h') * 100 + n + fn(n, 1) + q->y;
}

static double half(d) double d; { return d / 2; }
int implicit(x, y) long y; { return x * (int)y; }
void arr(buf, len) char buf[]; unsigned len; { buf[len - 1] = 0; }
static unsigned char lo(v) unsigned short v; { return (unsigned char)v; }
char *pick(a, b, which) char *a, *b; int which; { return which ? b : a; }

int main()
{
    Pt pt = { 7, 0 }, qq = { 0, 40 };
    char b[4] = "abc";
    arr(b, 2);
    printf("%d %ld %g %d %s\n", add(2, 3), mix(&pt, "hi", 5, add, &qq), half(3.0),
           implicit(6, 7L), b);
    printf("%d %s\n", lo(0x1234), pick("first", "second", 1));
    return 0;
}
