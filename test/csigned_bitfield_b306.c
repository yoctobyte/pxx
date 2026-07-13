/* Signed bitfields must sign-extend on read.

   A signed bitfield stores a two's-complement value in `width` bits.
   IRLowerBitFieldRead shifted and masked but never sign-extended, so every signed
   bitfield came back ZERO-extended: `signed f : 7` holding -5 read as 123, -3 in a
   3-bit field read as 5, -1 in a 1-bit field read as 1.

   An IR-level bug, so it was wrong on every backend, and completely silent: the C
   corpora (lua, sqlite, tcc, zlib) all use UNSIGNED bitfields, so none of them ever
   touched it. csmith's fourth random program found it.

   Expected output is gcc's, verbatim. */
int printf(const char *, ...);

struct A { signed a : 7; };
struct B { signed a : 3; signed b : 5; unsigned c : 4; };
struct C { int a : 1; };
struct D { signed a : 20; signed b : 19; unsigned c : 18; signed d : 7; };

static struct A ga = {-5};
static struct B gb = {-3, -9, 7};
static struct C gc = {-1};
static struct D gd = {140, 560, 423, -5};

/* signed fields that exactly fill their storage unit (8 and 16 bits) */
struct E { signed f : 8; };
struct S16 { signed f : 16; };
static struct E ge;
static struct S16 gs;

int main(void)
{
    struct A la;
    struct B lb;

    printf("A.a=%d\n", (int)ga.a);
    printf("B.a=%d B.b=%d B.c=%u\n", (int)gb.a, (int)gb.b, (unsigned)gb.c);
    printf("C.a=%d\n", (int)gc.a);
    printf("D.a=%d D.b=%d D.c=%u D.d=%d\n",
           (int)gd.a, (int)gd.b, (unsigned)gd.c, (int)gd.d);

    /* locals, and a value written at runtime rather than initialised */
    la.a = -2;
    printf("local A.a=%d\n", (int)la.a);
    lb.a = 3; lb.b = -16; lb.c = 15;
    printf("local B.a=%d B.b=%d B.c=%u\n", (int)lb.a, (int)lb.b, (unsigned)lb.c);

    /* boundary values: the most negative and most positive a 5-bit signed field holds */
    lb.b = -16; printf("min5=%d\n", (int)lb.b);
    lb.b = 15;  printf("max5=%d\n", (int)lb.b);
    lb.b = 0;   printf("zero=%d\n", (int)lb.b);

    /* an unsigned field must stay zero-extended */
    lb.c = 15;  printf("u4=%u\n", (unsigned)lb.c);

    /* A signed field that exactly FILLS its storage unit still needs the extension:
       the unit is loaded with an unsigned type, so it comes back zero-extended.
       Guarding the sign-extend on "narrower than the unit" left this reading 249. */
    ge.f = -7;  printf("full8=%d\n", (int)ge.f);
    ge.f = 127; printf("full8max=%d\n", (int)ge.f);
    gs.f = -300; printf("full16=%d\n", (int)gs.f);
    return 0;
}
