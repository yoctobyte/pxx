/* Global array decl with aggregate initializer, and balanced-brace skip so inner
   commas don't truncate the parse (lua's `static const luaL_Reg funcs[] = {...}`).
   Exit 42. */
struct KV { const char *name; int v; };
static struct KV tbl[] = { {"a", 1}, {"b", 2}, {"c", 3} };
static int counts[4] = { 10, 20, 30, 40 };
int after_decls(int x) { return x; }   /* must still parse after the init */
int main(void) {
  int local[3] = { 7, 8, 9 };          /* local init, balanced skip */
  local[0] = 42;
  return after_decls(local[0]);
}
