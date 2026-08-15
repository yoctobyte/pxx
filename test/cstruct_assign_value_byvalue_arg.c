/* A STRUCT assignment used as a VALUE and handed to a BY-VALUE parameter must
   pass the WHOLE struct. It passed the first eightbyte and left the rest stack
   garbage, because ResolveNodeRec had no arm for AN_ASSIGN: the argument
   resolved to REC_NONE, and the record temp the C by-value path allocates was
   sized by the REC_NONE fallback of 8 bytes rather than by the struct's own
   size. bug-c-a-struct-assignment-passed-by-value-copies-only-eight-bytes

   The sibling of cstruct_assign_value_side_effects.c: that one pins how many
   times the right-hand side RUNS, this one pins what the expression's VALUE is.
   Both come from csmith — seed 90202 and seed 91110 — and neither is reachable
   from the human-written corpora, because a program a person writes stores the
   struct and then passes the variable.

   The struct is 16 bytes with the payload in the SECOND eightbyte on purpose:
   an 8-byte copy gets f0 right and f1 wrong, so a test that only checked the
   first field would have passed. Exit 0 on agreement; each check exits with its
   own number. Verified against gcc on the same source. */
#include <stdio.h>

struct S1 { int f0; long long f1; };
struct Big { long long a, b, c; };

static struct S1 g = {1, 2};
static struct Big gb = {0, 0, 0};

static int take(struct S1 p) { return (p.f0 == 0x6F1F9E91) && (p.f1 == 0x0102030405060708LL); }
static int take_big(struct Big p) { return (p.a == 11) && (p.b == 22) && (p.c == 33); }
static int take2(struct S1 p, struct S1 q) { return (p.f1 == 0x0102030405060708LL) && (q.f1 == 77); }

int main(void) {
  struct S1 l = {0x6F1F9E91, 0x0102030405060708LL};
  struct S1 other = {5, 77};
  struct Big lb = {11, 22, 33};
  struct S1 *pg = &g;
  struct Big *pgb = &gb;

  /* through a DEREF destination — the shape csmith generated */
  if (!take((*pg) = l)) return 1;
  if (g.f1 != 0x0102030405060708LL) return 2;

  /* through a plain NAMED destination */
  g.f0 = 0; g.f1 = 0;
  if (!take(g = l)) return 3;

  /* a struct too big for any register pair, so the copy size cannot be
     accidentally right */
  if (!take_big((*pgb) = lb)) return 4;
  if (gb.c != 33) return 5;

  /* two such arguments in one call, so a shared temp would show up */
  g.f0 = 0; g.f1 = 0;
  {
    struct S1 g2 = {0, 0};
    if (!take2(g = l, g2 = other)) return 6;
    if (g2.f1 != 77 || g.f1 != 0x0102030405060708LL) return 7;
  }

  printf("ok\n");
  return 0;
}
