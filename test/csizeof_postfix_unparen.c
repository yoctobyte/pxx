/* The operand of the unary `sizeof` form is a unary-expression, so a whole
   postfix chain is legal there. `[]` was missing: `sizeof a[0]` — and with it
   `sizeof a / sizeof a[0]`, THE way C spells "how many elements", written
   unparenthesised throughout the Linux kernel and the BSD sources — was a hard
   parse error. Every value below is what gcc produces for this file.
   bug-cfront-sizeof-unparenthesised-subscript */

struct S { int x; char buf[16]; struct S *next; };

static int a[7];
static double b;
static int m[3][5];
static struct S s;
static struct S sa[4];
static struct S *p = sa;
static const char *names[] = { "a", "b", "c" };

static int f(void) { return 0; }

#define ARRAY_SIZE(x) (sizeof x / sizeof x[0])

#define CHECK(expr, want) do { if ((int)(expr) != (want)) return 1; } while (0)

int main(void) {
  struct S *q = &s;

  CHECK(sizeof b, 8);                    /* the pre-existing unary form   */
  CHECK(sizeof(b), 8);
  CHECK(sizeof *p, 32);

  CHECK(sizeof a[0], 4);                 /* the subscript that was missing */
  CHECK(sizeof(a[0]), 4);
  CHECK(sizeof a / sizeof a[0], 7);
  CHECK(ARRAY_SIZE(a), 7);
  CHECK(ARRAY_SIZE(names), 3);
  CHECK(ARRAY_SIZE(sa), 4);

  CHECK(sizeof m, 60);                   /* multidim: one subscript peels  */
  CHECK(sizeof m[0], 20);                /* ONE dimension, not to the elem */
  CHECK(sizeof m[0][0], 4);
  CHECK(ARRAY_SIZE(m), 3);

  CHECK(sizeof s.buf, 16);               /* the rest of the postfix set    */
  CHECK(sizeof q->buf, 16);
  CHECK(sizeof sa[1], 32);
  CHECK(sizeof sa[1].buf, 16);
  CHECK(sizeof p[2].buf, 16);
  CHECK(sizeof q->next->buf, 16);
  CHECK(sizeof f(), 4);

  return 42;
}
