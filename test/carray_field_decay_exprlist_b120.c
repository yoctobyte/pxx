/* SQLite-shaped fixed-array field decay: the array element begins with a
   pointer and contains a nested bitfield struct. `struct Item *a = list->a`
   must store the address of the first item, not load item[0].pExpr. Exit 42. */
struct Expr {
  unsigned char op;
  unsigned int flags;
};

struct Item {
  struct Expr *pExpr;
  char *zEName;
  struct {
    unsigned char sortFlags;
    unsigned eEName : 2;
    unsigned done : 1;
    unsigned reusable : 1;
  } fg;
};

struct List {
  int nExpr;
  int nAlloc;
  struct Item a[1];
};

int main(void) {
  struct Expr expr;
  struct List list;
  struct List *pList = &list;
  struct Item *a;

  expr.op = 180;
  expr.flags = 7;
  list.nExpr = 1;
  list.nAlloc = 1;
  list.a[0].pExpr = &expr;
  list.a[0].zEName = 0;
  list.a[0].fg.sortFlags = 0;
  list.a[0].fg.eEName = 0;

  a = pList->a;
  if (a != &list.a[0]) return 1;
  if (a[0].pExpr->op != 180) return 2;
  return 42;
}
