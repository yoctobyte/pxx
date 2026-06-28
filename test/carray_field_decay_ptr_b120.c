/* A fixed array field used as an expression decays to the field address. In
   particular, `p = list->a` must not load the first element and use that as the
   pointer. SQLite's selectExpander has this exact shape:
   `struct ExprList_item *a = pEList->a`. Exit 42. */
struct Item {
  int value;
};

struct List {
  int n;
  struct Item a[2];
};

int main(void) {
  struct List list;
  struct List *pList = &list;
  struct Item *p;

  list.n = 2;
  list.a[0].value = 11;
  list.a[1].value = 31;

  p = pList->a;
  if (p != &list.a[0]) return 1;
  return p[0].value + p[1].value;
}
