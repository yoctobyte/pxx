/* A static initialiser `&(&global)->member` (FreeBSD SYSCTL_CHILDREN of a
   static sysctl node) is a constant address: *&x is x.
   bug-c-a-global-initialised-to-the-address-of-a-member-through-an-address-is-not-constant.
   Built hosted and as a --freestanding object (where a non-constant
   initialiser is refused). Expected output is gcc's. */
#include <stdio.h>
struct list { void *first; };
struct oid { struct list *parent; struct list children; const char *name; int num; };
struct oid root = { 0, { 0 }, "root", 1 };
#define CHILDREN(p) (&(p)->children)
struct oid kid = { CHILDREN(&root), { 0 }, "kid", 2 };
static struct list *lp = &(*&root).children;
int main(void) {
  printf("%d %d %s\n", kid.parent == &root.children, lp == &root.children, kid.name);
  return 0;
}
