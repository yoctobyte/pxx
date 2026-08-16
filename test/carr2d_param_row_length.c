/* `void f(int a[][4])` — the ordinary way a 2-D array is passed to a function.
   The parameter declarator's brackets were consumed by a blind balanced skip,
   so the row length 4 was lost and the pointee looked like a plain `int *`:
   `a[1][2]` flattened to 1+2 and read a[0][3]. A wrong VALUE, silently, while
   the equivalent `int (*a)[4]` spelling was right — the two forms mean the same
   thing in C and disagreed here.
   bug-c-a-2d-array-parameter-loses-its-row-length */
#include <stdio.h>

int m[3][4];
int t[2][3][4];

static int fails;
static void chk(const char *what, int got, int want)
{
    if (got != want) { printf("FAIL %s: got %d want %d\n", what, got, want); fails++; }
}

static int two(int a[][4])          { return a[1][2]; }
static int twoStar(int (*a)[4])     { return a[1][2]; }
static int three(int a[][3][4])     { return a[1][2][3]; }
static int sized(int a[3][4])       { return a[2][1]; }
static int total(int n, int a[][4])
{
    int s = 0;
    for (int i = 0; i < n; i++)
        for (int j = 0; j < 4; j++) s += a[i][j];
    return s;
}
static int one(int a[])             { return a[2]; }
static int oneSized(int a[5])       { return a[4]; }
static int ptrs(char *a[])          { return a[1][0]; }

int main(void)
{
    int flat[5] = {10, 11, 12, 13, 14};
    char *names[2] = {"a", "b"};

    for (int i = 0; i < 3; i++)
        for (int j = 0; j < 4; j++) m[i][j] = i * 4 + j;
    t[1][2][3] = 7;

    chk("[][4]",        two(m),       6);
    chk("(*)[4]",       twoStar(m),   6);
    chk("[][3][4]",     three(t),     7);
    chk("[3][4]",       sized(m),     9);
    chk("sum",          total(3, m),  66);
    /* the one-dimensional and pointer-array forms are untouched by this */
    chk("[]",           one(flat),    12);
    chk("[5]",          oneSized(flat), 14);
    chk("char *[]",     ptrs(names),  'b');

    if (fails == 0) printf("ok\n");
    return 42 + fails;
}
