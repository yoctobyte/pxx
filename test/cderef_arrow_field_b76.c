/* `(*p)->field` — arrow on a dereferenced double pointer. The base `*p` is a
   pointer value, so `->` must deref it and apply the field offset to that
   value; previously `*p` was not recognized as a pointer (no AN_DEREF case in
   CNodeIsPointer/CNodePtrElemRec), so the field was taken from the slot holding
   `*p` (it read/addressed `p`'s own storage), with non-zero field offsets
   collapsing to 0. This is lua's `for (p=&g->allgc; *p!=o; p=&(*p)->next)`
   list-walk idiom, which otherwise looped forever. */

extern long __pxx_write(int, const void *, unsigned long);

typedef struct Node { struct Node *next; int tag; } Node;

static Node a, b, c;

int main(void) {
  Node *head;
  Node **p;
  a.next = &b; a.tag = 1;
  b.next = &c; b.tag = 2;
  c.next = 0;  c.tag = 3;
  head = &a;
  p = &head;          /* *p == head == &a */

  /* values through (*p)-> */
  if ((*p)->next != &b) return 1;                /* field at offset 0 */
  if ((*p)->tag != 1) return 2;                  /* field at offset 8 */

  /* address-of field through (*p)-> must equal base ptr (+ offset) */
  if (&(*p)->next != (Node **)&a) return 3;
  if ((char *)&(*p)->tag != (char *)&a + 8) return 4;

  /* the lua list-walk: advance via p = &(*p)->next, find &c */
  {
    int n = 0;
    for (p = &head; *p != &c; p = &(*p)->next) {
      if (++n > 10) return 5;                     /* runaway = the old bug */
    }
    if (*p != &c) return 6;
    if (n != 2) return 7;                          /* walked a, b */
  }
  return 42;
}
