/* Pointer ARITHMETIC and pointer DIFFERENCE must use the element stride for
   every element type, including the signed 64-bit ones.

   They did not. An AN_IDENT for `long long a[8]` carries tyInt64 — its element
   kind — and IRNodePointerBase bailed out on tyInt64 outright, so a signed
   64-bit array was never a pointer base: `a + 1` stepped ONE BYTE and `q - p`
   came back 0. `unsigned long long a[8]` (tyUInt64) was correct, so a SIGN BIT
   decided a stride. `a[1]` was always right, because indexing scales itself,
   which is why the layout looked fine and only the decayed form was wrong.

   The tyInt64 bail was not gratuitous: cparser's partial-index builder retags
   its base tyInt64 as a SENTINEL meaning "raw byte add, already scaled" (`m[1]`
   on `int m[3][4]`). carr2d_decay_stride.c pins that side; this file pins the
   other, and the two together are what the tag has to keep apart.
   bug-c-pointer-difference-on-a-long-long-element-type

   Every expected value is gcc's, on the same source. Exit 42 on agreement. */
#include <stdio.h>

typedef struct { long long a, b; } S16;
typedef struct { int x; } S4;

static int fails;
static void chk(const char *what, int got, int want)
{
    if (got != want) { printf("FAIL %s: got %d want %d\n", what, got, want); fails++; }
}

/* decay stride in BYTES, and ptrdiff in ELEMENTS, for one element type */
#define DECAY(ty, nm, sz)                                                     \
    { ty z[8]; ty *p = z, *q = z + 3;                                         \
      chk(nm " decay",  (int)((char *)(z + 1) - (char *)z), sz);              \
      chk(nm " diff",   (int)(q - p), 3);                                     \
      chk(nm " diffarr",(int)(q - z), 3);                                     \
      chk(nm " index",  (int)((char *)&z[1] - (char *)&z[0]), sz); }

long long g_ll[8];
long      g_l[8];

int main(void)
{
    long long *gp;

    DECAY(char,               "char",   1)
    DECAY(short,              "short",  2)
    DECAY(int,                "int",    4)
    DECAY(unsigned,           "uint",   4)
    DECAY(long,               "long",   8)
    DECAY(unsigned long,      "ulong",  8)
    DECAY(long long,          "ll",     8)
    DECAY(unsigned long long, "ull",    8)
    DECAY(float,              "float",  4)
    DECAY(double,             "double", 8)
    DECAY(S4,                 "S4",     4)
    DECAY(S16,                "S16",    16)

    /* a GLOBAL signed 64-bit array takes the same path */
    gp = g_ll + 3;
    chk("global ll decay", (int)((char *)gp - (char *)g_ll), 24);
    chk("global ll diff",  (int)(gp - g_ll), 3);
    chk("global l decay",  (int)((char *)(g_l + 3) - (char *)g_l), 24);

    /* the forms that were never broken, kept so a fix cannot trade them */
    { long long a[8], *p = a; p += 3;
      chk("ptrvar +=", (int)((char *)p - (char *)a), 24);
      p = a; p++;
      chk("ptrvar ++", (int)((char *)p - (char *)a), 8);
      p = &a[3];
      chk("addr of elem", (int)((char *)p - (char *)a), 24); }

    /* walking a long long array through a pointer must visit every element */
    { long long a[4], *p, s = 0; int i;
      for (i = 0; i < 4; i++) a[i] = i + 1;
      for (p = a; p < a + 4; p++) s += *p;
      chk("walk sum", (int)s, 10); }

    if (fails == 0) printf("ok\n");
    return 42 + fails;
}
