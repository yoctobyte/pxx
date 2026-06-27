/* File-scope function-pointer ARRAY declarator `int (*const arr[])(T)`, the
   shape of sqlite's sqlite3BuiltinExtensions[]. ParseCDeclType consumes the
   whole declarator (name + `[]`) into CTypeFnPtrName/CTypeFnPtrArrLen, so the
   global must be registered HERE as an array of callable pointers and the brace
   initializer materialised as per-element proc addresses — otherwise every
   `arr[i]` reference folded to a bare 0 and crashed IR codegen
   (bug-c-null-pointer-literal-call-arg-sqlite).

   Also guards the regression that a struct/union global whose LAST member is a
   function pointer (`struct { void (*f)(void); } g;`) leaves CTypeFnPtrName set
   as leftover: it must still route through the normal record-var path. Exit 42. */

typedef struct Ctx Ctx;
struct Ctx { int seed; };

static int extA(Ctx *c) { return c->seed + 1; }
static int extB(Ctx *c) { return c->seed + 2; }
static int extC(Ctx *c) { return c->seed + 4; }

/* unbounded `[]` const fn-ptr array, exactly sqlite's declarator */
static int (*const exts[])(Ctx*) = { extA, extB, extC };

#define ArraySize(X) ((int)(sizeof(X) / sizeof(X[0])))

/* struct global whose last field is a fn pointer + an initializer — the branch
   guard (baseTk = tyPointer) must NOT hijack this as a fn-ptr declarator. */
static struct Hooks {
  void (*xBegin)(void);
  void (*xEnd)(void);
} gHooks = { 0, 0 };

static void markBegin(void) { }

int main(void) {
  Ctx c;
  int i, rc = 0;
  c.seed = 0;
  /* indexed call-through a fn-ptr array element, the sqlite loop shape */
  for (i = 0; i < ArraySize(exts); i++) {
    rc += exts[i](&c);
  }
  /* exts: (0+1) + (0+2) + (0+4) = 7 */

  /* the struct global must be a real, assignable record */
  gHooks.xBegin = markBegin;
  if (gHooks.xBegin == markBegin && gHooks.xEnd == 0) rc += 35;

  return rc; /* 7 + 35 = 42 */
}
