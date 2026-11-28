/* An array-of-structs member decays to a pointer: assigned, offset, reached
   through a call (amdgpu_res_cursor.h, a flexible `mm_nodes[]`).
   bug-c-an-array-of-structs-member-is-refused-as-a-struct-operand.
   Expected output is gcc's. */
#include <stdio.h>
#include <stdlib.h>
struct node { long size; int tag; };
struct mgr { int base; struct node nodes[]; };
static struct mgr *to_mgr(void *p) { return (struct mgr *)p; }
int main(void) {
  struct mgr *m = malloc(sizeof(struct mgr) + 3 * sizeof(struct node));
  for (int i = 0; i < 3; i++) { m->nodes[i].size = 10 * (i + 1); m->nodes[i].tag = i; }
  struct node *n = to_mgr(m)->nodes;
  struct node *k = m->nodes;
  long s = 0;
  while (n->tag < 2) s += n++->size;
  printf("%ld %ld %d\n", s, k[2].size, (to_mgr(m)->nodes + 1)->tag);
  return 0;
}
