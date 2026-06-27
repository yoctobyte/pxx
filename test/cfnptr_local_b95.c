/* Function-pointer LOCAL variable with initializer:
   `RET (*name)(params) = init;` — ParseCDeclType consumes the whole declarator
   and captures the name, so ParseCLocalDeclAST must allocate the local under
   that name as a callable 8-byte pointer (not Break on the already-consumed
   name). sqlite3OsSectorSize shape. Exit 42. */
typedef int sqlite3_file;
struct M { int (*xSectorSize)(sqlite3_file*); };
struct F { struct M *pMethods; };
static int call(sqlite3_file *id, struct F *f){
  int (*xSectorSize)(sqlite3_file*) = f->pMethods->xSectorSize;
  return (xSectorSize ? xSectorSize(id) : 4096);
}
int sz(sqlite3_file *p){ return 42; }
int main(void){
  struct M m; m.xSectorSize = sz;
  struct F f; f.pMethods = &m;
  return call(0, &f);
}
