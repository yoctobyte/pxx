/* Anonymous bit-fields: `T : width` (padding) and `T : 0` (alignment directive).

   Neither declares a member; both reserve bits. `T : 0` forces the NEXT bit-field to
   start a fresh storage unit.

   pxx REJECTED any aggregate containing one and fell back to an opaque record --
   sizeof came out 0 and every field read back garbage. Silently: no error, no warning,
   and a struct whose members were otherwise perfectly ordinary. Anything holding such
   a struct was quietly wrong.

   ParseCStructInto now models them (reserve the bits, register no field), so the opaque
   fallback is gone. csmith emits them constantly (`volatile unsigned : 0;` in a union),
   which is how this surfaced; no real-world corpus we run had ever tripped it.

   Expected output is gcc's, verbatim. */
int printf(const char *, ...);

struct A { unsigned a : 3; unsigned : 2; unsigned b : 3; };        /* padding */
struct B { unsigned long x; unsigned : 0; unsigned long y; };      /* :0 alignment */
struct C { unsigned a : 3; unsigned b : 3; };                      /* control: no anon */
struct D { unsigned a : 3; unsigned : 0; unsigned b : 3; };        /* :0 splits the unit */
union  U { unsigned long f0; volatile unsigned : 0; };             /* csmith's shape */

static struct A a = {5, 6};
static struct B b = {11, 22};
static struct C c = {5, 6};
static struct D d = {5, 6};
static union  U u = {18446744073709551612UL};

int main(void)
{
    printf("A size=%d a=%u b=%u\n", (int)sizeof(struct A), a.a, a.b);
    printf("B size=%d x=%lu y=%lu\n", (int)sizeof(struct B), b.x, b.y);
    printf("C size=%d a=%u b=%u\n", (int)sizeof(struct C), c.a, c.b);
    printf("D size=%d a=%u b=%u\n", (int)sizeof(struct D), d.a, d.b);
    printf("U size=%d f0=%lu\n", (int)sizeof(union U), u.f0);

    /* writes must land in the right bits, with the padding skipped */
    a.a = 7; a.b = 1;
    printf("A written a=%u b=%u\n", a.a, a.b);
    d.a = 2; d.b = 7;
    printf("D written a=%u b=%u\n", d.a, d.b);
    return 0;
}
