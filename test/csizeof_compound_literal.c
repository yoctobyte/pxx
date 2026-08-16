/* `sizeof((int[]){1,2,3})` — an array COMPOUND LITERAL is an object of array
   type. Only its USE decays to a pointer, and sizeof is not a use; pxx sized
   it by the result type of the expression and answered 8 for every one of
   them. That is what the NARGS idiom counts with:

     #define NARGS(...) (sizeof((int[]){__VA_ARGS__}) / sizeof(int))

   which therefore answered 2 for any argument list, silently.
   bug-c-sizeof-an-array-compound-literal */
#include <stdio.h>

#define NARGS(...) (int)(sizeof((int[]){__VA_ARGS__}) / sizeof(int))

struct P { int a, b; };

static int fails;
static void chk(const char *what, int got, int want)
{
    if (got != want) { printf("FAIL %s: got %d want %d\n", what, got, want); fails++; }
}

int main(void)
{
    int *p = (int[]){7, 8, 9};

    chk("unsized-3",   (int)sizeof((int[]){1, 2, 3}), 12);
    chk("unsized-1",   (int)sizeof((int[]){1}), 4);
    chk("chars",       (int)sizeof((char[]){1, 2, 3, 4, 5}), 5);
    chk("sized",       (int)sizeof((int[4]){0}), 16);
    chk("doubles",     (int)sizeof((double[]){1.0, 2.0}), 16);
    chk("nargs-3",     NARGS(1, 2, 3), 3);
    chk("nargs-1",     NARGS(9), 1);
    chk("nargs-5",     NARGS(1, 2, 3, 4, 5), 5);

    /* the shapes that already worked, and must keep working: a record compound
       literal, the literal's VALUE, and sizeof of an ordinary expression */
    chk("record",      (int)sizeof((struct P){1, 2}), 8);
    chk("value",       p[1] + p[2], 17);
    chk("expr",        (int)sizeof(p[0] + 1), 4);
    chk("type",        (int)sizeof(int[3]), 12);

    if (fails == 0) printf("ok\n");
    return 42 + fails;
}
