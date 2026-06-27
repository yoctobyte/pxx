/* Struct field arrays whose elements are pointers must use full pointer-width
   stores and loads. Lua's global_State.tmname[] has this shape. Exit 42. */
struct Obj { int v; };
struct Holder { struct Obj *items[2]; };

static struct Obj a = { 19 };
static struct Obj b = { 23 };

int main(void) {
  struct Holder h;
  h.items[0] = &a;
  h.items[1] = &b;
  return h.items[0]->v + h.items[1]->v;
}
