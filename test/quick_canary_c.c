/* Quick-tier C canary (feature-t-quick-canary-for-nilpy-and-c).
 *
 * BROAD, not deep: a line or two per layer that actually breaks, so a Track C
 * or shared-parser/IR change gets a cheap signal inside the ~12s dev loop. It
 * is a CANARY, not coverage -- coverage is the C suites and Track T's matrix.
 *
 * Every section prints its own `ok <n>` BEFORE the summary, so a failure
 * localises instead of collapsing to one opaque mismatch. The last line is the
 * oracle the Makefile compares. Also compiles and runs under gcc, so the
 * expectations can be checked against the reference implementation.
 */
#include <stdio.h>
#include <stdarg.h>
#include <string.h>

static int ok = 0;

static void chk(int n, int cond)
{
    if (cond) { ok++; printf("ok %d\n", n); }
    else      { printf("FAIL %d\n", n); }
}

struct Point { int x; int y; };

union U { int i; unsigned char b[4]; };

static int add(int a, int b) { return a + b; }
static int sub(int a, int b) { return a - b; }

static long sum_va(int count, ...)
{
    /* varargs: a wrong length modifier reads the wrong bytes off the stack
       with no diagnostic anywhere, so it is worth a canary line */
    long total = 0;
    va_list ap;
    va_start(ap, count);
    for (int i = 0; i < count; i++)
        total += va_arg(ap, int);
    va_end(ap);
    return total;
}

int main(void)
{
    /* --- integer promotion and arithmetic --------------------------------- */
    unsigned short us = 40000;
    chk(1, -(int)us == -40000);            /* unary minus promotes to signed int */
    chk(2, (7 / 2) == 3 && (7 % 2) == 1);
    chk(3, (-7 / 2) == -3);                /* C truncates toward zero, unlike Python */
    long big = 1000000L;
    chk(4, big * big == 1000000000000L);
    chk(5, (1 << 10) == 1024);
    chk(6, (unsigned char)300 == 44);

    /* --- pointers and arrays ---------------------------------------------- */
    int arr[5];
    for (int i = 0; i < 5; i++) arr[i] = i * i;
    int *p = arr;
    chk(7, p[3] == 9 && *(p + 4) == 16);
    chk(8, (int)(sizeof(arr) / sizeof(arr[0])) == 5);
    int (*fn)(int, int) = add;
    chk(9, fn(2, 3) == 5);
    fn = sub;
    chk(10, fn(9, 4) == 5);

    /* --- structs and unions ----------------------------------------------- */
    struct Point pt;
    pt.x = 3; pt.y = 4;
    struct Point copy = pt;                /* by-value copy */
    copy.x = 99;
    chk(11, pt.x == 3 && copy.x == 99);
    struct Point *pp = &pt;
    chk(12, pp->x + pp->y == 7);
    union U u;
    u.i = 0;
    u.b[0] = 1;
    chk(13, u.i == 1);                     /* little-endian */

    /* --- strings ----------------------------------------------------------- */
    char buf[32];
    strcpy(buf, "Hello");
    strcat(buf, ", World");
    chk(14, strlen(buf) == 12);
    chk(15, strcmp(buf, "Hello, World") == 0);
    chk(16, strncmp(buf, "Hello", 5) == 0);
    chk(17, strchr(buf, 'W') != 0);

    /* --- control flow ------------------------------------------------------ */
    int tot = 0;
    for (int i = 0; i < 5; i++) {
        if (i % 2 == 0) continue;
        tot += i;
    }
    chk(18, tot == 4);

    int sw = 0;
    switch (3) {
        case 1: sw = 10; break;
        case 3: sw = 30; /* fallthrough */
        case 4: sw += 4; break;
        default: sw = -1;
    }
    chk(19, sw == 34);

    int w = 0, n = 0;
    while (n < 4) { w += n; n++; }
    chk(20, w == 6);

    /* --- varargs and printf formatting ------------------------------------- */
    chk(21, sum_va(4, 1, 2, 3, 4) == 10);
    char fbuf[64];
    sprintf(fbuf, "%d|%s|%c|%ld", 42, "str", 'x', 123456789L);
    chk(22, strcmp(fbuf, "42|str|x|123456789") == 0);

    printf("total ok %d / 22\n", ok);
    return 0;
}
