/* A CAST inside a static aggregate initializer folded to 0 — for every type,
   `(char)1` included, so a static table built from casts became all zeros with
   no diagnostic. Nothing warned and nothing crashed; a zero-filled lookup table
   usually looks plausible and fails far away.

   The tell: a cast through a TYPEDEF name already worked, because that is a
   tkIdent and the flat-init pre-scan allowed it, while the KEYWORD spelling of
   the same cast bailed off that path. One spelling of one expression apart.
   bug-cfront-cast-in-static-aggregate-initializer-folds-to-zero

   Expectations are gcc's, measured. Note c3/u2: the array element is a plain
   `char`, which is SIGNED on x86-64/i386, so 0xFF reads back as -1 there — the
   two rules interact, hence the guard. */

#if defined(__x86_64__) || defined(__i386__)
#  define CH_FF (-1)
#else
#  define CH_FF 255
#endif

typedef int myint;
struct pair { int a; char b; };

/* Every cast spelling, at file scope. */
int            b1[2] = { (int)0xFF, 0 };
int            b2[2] = { (myint)0xFF, 0 };        /* typedef: always worked */
char           c1[2] = { (char)1, 0 };
char           c2[2] = { (char)0x7F, 0 };
char           c3[2] = { (unsigned char)0xFF, 0 };
signed char    s1[2] = { (signed char)0xFF, 0 };
unsigned char  u2[2] = { (unsigned char)200, 0 };
short          h1[2] = { (short)0xFF, 0 };
long           l1[2] = { (long)0xFF, 0 };
unsigned int   v1[2] = { (unsigned)0xFF, 0 };
int            e1[2] = { (int)0xFF + 1, 0 };      /* cast inside an expression */
int            e2[2] = { ((int)0xFF) << 2, 0 };
int            e3[2] = { 1 + 1, 0 };              /* no cast: always worked */

/* Structs, not just arrays. */
struct pair    p1    = { (int)0xFF, (char)1 };

/* A static LOCAL takes the same path as a file-scope one. */
static int     sl[2] = { (int)0xFF, 0 };

/* NESTED aggregates bail off the flat path on their opening brace and were
   never affected — pinned gets these right. Here so a future change to the
   flat-init pre-scan cannot quietly break them instead. */
int            m2[2][2] = { { (int)0xFF, 1 }, { 2, 3 } };
struct pair    pa[2]    = { { (int)0xFF, (char)1 }, { 2, 3 } };

int main(void) {
    /* A non-static local was always correct — it must stay correct. */
    int loc[2] = { (int)0xFF, 0 };

    if (b1[0] != 255) return 1;
    if (b2[0] != 255) return 2;
    if (c1[0] != 1) return 3;
    if (c2[0] != 127) return 4;
    if (c3[0] != CH_FF) return 5;
    if (s1[0] != -1) return 6;
    if (u2[0] != 200) return 7;
    if (h1[0] != 255) return 8;
    if (l1[0] != 255) return 9;
    if (v1[0] != 255u) return 10;
    if (e1[0] != 256) return 11;
    if (e2[0] != 1020) return 12;
    if (e3[0] != 2) return 13;
    if (p1.a != 255) return 14;
    if (p1.b != 1) return 15;
    if (sl[0] != 255) return 16;
    if (loc[0] != 255) return 17;

    /* The rest of the array is still zero-filled, i.e. the fix did not shift
       elements or mis-count the flat initializer's length. */
    if (b1[1] != 0 || c1[1] != 0 || l1[1] != 0) return 18;

    if (m2[0][0] != 255 || m2[1][1] != 3) return 19;
    if (pa[0].a != 255 || pa[0].b != 1 || pa[1].a != 2) return 20;

    return 42;
}
