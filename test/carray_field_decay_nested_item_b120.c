/* Same decay as carray_field_decay_exprlist_b120, but with the element struct
   declared inside the parent record, matching SQLite's ExprList_item. Exit 42. */
struct Expr {
  unsigned char op;
  unsigned int flags;
};

struct List {
  int nExpr;
  int nAlloc;
  struct Item {
    struct Expr *pExpr;
    char *zEName;
    struct {
      unsigned char sortFlags;
      unsigned eEName : 2;
      unsigned done : 1;
      unsigned reusable : 1;
    } fg;
  } a[1];
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
