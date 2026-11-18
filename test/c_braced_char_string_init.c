/* A char array initialised by a braced string literal, C11 6.7.9p14. TinyX's
   colour table is `static const char Names[] = { "alice blue\0" ... };`, and
   pxx made it 1 byte long and empty. The forms whose braces mean something
   else (arrays of pointers, 2-D arrays, structs) must keep their meaning.
   bug-c-a-braced-string-initialiser-for-a-char-array-is-empty */
#include <stdio.h>
#include <string.h>

static const char Names[] = {
    "alice blue\0"
        "AliceBlue\0"
        "black\0"
        "white\0"
};
static const char A[] = { "abc" };
static char C[8] = { "xyz", };
unsigned char U[] = { "uv" };
static const char *P[] = { "ptr" };
static char D[][4] = { "ab" };
struct S { char s[6]; int n; };
static struct S st = { "hello", 3 };

int main(void)
{
    const char L[] = { "loc" "al" };
    signed char SG[5] = { "sg" };
    int i, n = 0;
    for (i = 0; i < (int)sizeof Names; i += (int)strlen(&Names[i]) + 1) n++;
    printf("%d %d %s | %d %s | %d %s | %d %s\n", (int)sizeof Names, n, &Names[21],
           (int)sizeof A, A, (int)sizeof C, C, (int)sizeof U, (const char *)U);
    printf("%d %s | %d %s | %s %d\n", (int)sizeof L, L, (int)sizeof SG, (const char *)SG,
           P[0], (int)sizeof P);
    printf("%d %s | %s %d\n", (int)sizeof D, D[0], st.s, st.n);
    return 0;
}
