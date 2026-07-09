/* b230: ((T *) base)[i].ptrfield must load/store as an 8-byte pointer even when
   the index base is a pointer CAST. ResolveNodeRec's AN_INDEX branch lost the
   element record for an AN_PTR_CAST base, so the field type defaulted to 4-byte
   int and truncated/sign-extended 8-byte pointer fields. This is duktape's value
   stack: `((duk_tval *) ...)[i].v.heaphdr` — the truncated pointer crashed
   duk_pcompile. */
typedef struct { int t; int pad; void *p; } Slot;
static void set_p(void *base, int i, void *val) { ((Slot *) base)[i].p = val; }
static void *get_p(void *base, int i) { return ((Slot *) base)[i].p; }
int main(void) {
  Slot arr[4];
  int local;
  set_p(arr, 1, &local);
  return (get_p(arr, 1) == (void *) &local) ? 42 : 1;
}
