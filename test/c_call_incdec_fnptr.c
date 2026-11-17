/* Calling through an incremented pointer into a table of function pointers:
   `(*p++)(args)`. pxx called through the wrong value (garbage result), and
   with the table pointer typedef'd -- Xlib's XcmsFuncListPtr, as walked in
   xcms/CvCols.c -- the call did not parse at all.
   bug-c-call-through-an-incremented-pointer-to-function-pointer */
#include <stdio.h>

typedef int (*F)(int, int);
typedef F *FL;                       /* Xcms: typedef XcmsConversionProc *XcmsFuncListPtr */

static int add(int a, int b) { return a + b; }
static int mul(int a, int b) { return a * b; }
static int sub(int a, int b) { return a - b; }

int main(void)
{
    F fs[4] = {add, mul, sub, 0};
    F *p = fs;
    int r = 0;
    while (*p != 0)
        r += (*p++)(6, 7);           /* 13 + 42 - 1 */
    printf("post %d %ld\n", r, (long)(p - fs));

    F *q = fs;
    int s = (*(q++))(1, 2);          /* add, then q -> mul */
    s += (*q)(3, 4);                 /* mul */
    s += (*++q)(10, 4);              /* sub */
    s += (*q--)(5, 5);               /* sub, then q -> mul */
    printf("mixed %d %ld\n", s, (long)(q - fs));

    FL t = fs;
    int u = 0;
    while (*t)
        u = u * 100 + (*t++)(9, 3);
    printf("typedef %d\n", u);

    /* CvCols.c's shape: the table hangs off a struct field and is copied
       into a local before the walk; indexing calls it directly too. */
    struct Space { const char *name; FL to_xyz; } sp = {"rgb", fs};
    FL w = sp.to_xyz;
    int v = 0;
    while (*w != 0)
        v += (*w++)(2, 3);
    printf("field %d %d %d\n", v, sp.to_xyz[1](4, 5), w[-1](8, 1));

    /* Sibling declarators share the base type: CvCols.c declares
       `XcmsDIConversionProc *to_CIEXYZ_stop, *from_CIEXYZ_start;` and walks
       the SECOND one. */
    F *a, *b, c;
    F e, *f;
    a = fs; b = fs; c = mul; e = add; f = fs + 1;
    int x = (*a)(1, 2);
    x = x * 100 + (*b++)(3, 4);
    x = x * 100 + (*b)(3, 4);
    printf("siblings %d %d %d\n", x, c(5, 6), e(1, 1) + (*f)(2, 2));
    return 0;
}
