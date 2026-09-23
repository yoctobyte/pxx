/* THE POPULATION THE INCOMPLETE-TYPE REFUSAL MUST NOT BREAK.
 *
 * The companion to test/c_incomplete_type_member_refused.c, and the more
 * important of the two: a pointer to an incomplete type is ordinary C, it is
 * how every opaque handle in every library is spelled, and this tree's own
 * headers use it. A refusal that reached these would take out FILE *, the
 * forward-declared list node, and the `struct opaque;' idiom entirely.
 *
 * The rule the refusal actually applies: a member may not be taken from a type
 * whose layout is unknown. DECLARING a pointer to such a type asks for no
 * layout, so nothing here is refused -- and a forward declaration that is later
 * DEFINED is not incomplete by the time a member is taken from it.
 *
 * Every row prints, so a shape that silently stopped working is visible as a
 * wrong number rather than as a missing line.
 * bug-c-an-undeclared-struct-type-compiles-and-reads-garbage
 */
#include <stdio.h>

struct opaque;                      /* declared, NEVER defined            */
struct opaque *g_opaque;            /* pointer to an incomplete type      */
extern struct opaque *handle_of(void);   /* and through a signature       */

struct fwd;                         /* forward-declared ...               */
struct fwd { int x; };              /* ... and then defined: NOT incomplete */

struct outer { struct fwd f; int y; };
union u { int i; char c[4]; };
struct bits { unsigned b3:3; unsigned rest:29; };

/* A self-referential type: incomplete AT THE POINT the member is declared,
   which is legal precisely because the member is a pointer. */
struct node { int v; struct node *next; };

int via_ptr(struct fwd *p) { return p->x; }
int chain(struct node *n) { return n->next->v; }

int main(void) {
  struct outer o; union u un; struct bits bf;
  struct node b, a;
  o.f.x = 1; o.y = 2; un.i = 3; bf.b3 = 4; bf.rest = 5;
  b.v = 7; b.next = 0; a.v = 6; a.next = &b;
  printf("%d %d %d %d %d\n", o.f.x, o.y, un.i, bf.b3, bf.rest);
  printf("%d %d %d\n", via_ptr(&o.f), chain(&a), g_opaque == 0);
  return 0;
}
