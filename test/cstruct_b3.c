/* Slice B increment 2b fixture: struct field access — value `.`, pointer `->`,
   struct-pointer parameters, nested structs, a typedef struct, and a linked
   list walked by pointer. Exit code asserted vs a gcc oracle. */
typedef struct { int w; int h; } Rect;
struct Node { int v; struct Node *next; };

int area(Rect *r) { return r->w * r->h; }

int sum_list(struct Node *p) {
  int s = 0;
  while (p) { s += p->v; p = p->next; }
  return s;
}

int main(void) {
  Rect r;
  r.w = 6; r.h = 7;
  int total = area(&r);              /* 42 */

  struct Node a, b, c;
  a.v = 10; a.next = &b;
  b.v = 20; b.next = &c;
  c.v = 30; c.next = 0;
  total += sum_list(&a) - 60;        /* (60) -> +0 = 42 */

  struct Node *p = &a;
  total += p->next->v;               /* b.v = 20 -> 62 */
  return total;                      /* 62 */
}
