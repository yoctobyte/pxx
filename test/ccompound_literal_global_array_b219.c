/* File-scope compound literal inside a global array initializer (gap C).
   `struct Wrap global_wrap[] = {((struct Wrap){inc_global}), inc_global}` — the
   global array walker's emit-mode leaf (ParseCExpr) now materialises the CL value.
   Also a local array-of-record with a CL element. -> 42. */
struct Wrap { void *func; };
int global;
void inc_global(void) { global++; }
struct Wrap global_wrap[] = {
  ((struct Wrap){inc_global}),
  inc_global,
};
int main(void) {
  struct Wrap local_wrap[] = { ((struct Wrap){inc_global}), inc_global, };
  void (*p)(void);
  p = global_wrap[0].func; p();
  p = global_wrap[1].func; p();
  p = local_wrap[0].func;  p();
  p = local_wrap[1].func;  p();
  return global == 4 ? 42 : 1;
}
