/* C function returning a function pointer:
   void (*name(params))(void). sqlite's sqlite3OsDlSym uses this shape and must
   be registered as a real function, not skipped as a function-pointer variable
   declaration. Exit 42. */
typedef void (*VoidFn)(void);
typedef struct Vfs Vfs;

struct Vfs {
  VoidFn (*xSym)(Vfs *, void *, const char *);
};

void target(void) {
}

VoidFn provider(Vfs *v, void *h, const char *z) {
  return target;
}

void (*lookup(Vfs *v, void *h, const char *z))(void);

void (*lookup(Vfs *v, void *h, const char *z))(void) {
  return v->xSym(v, h, z);
}

int main(void) {
  Vfs v;
  VoidFn f;
  v.xSym = provider;
  f = (VoidFn)lookup(&v, 0, "sym");
  return f == target ? 42 : 1;
}
