/* sizeof of a parenthesized-then-indexed operand: `sizeof((l)[0])` — the skip to
   the matching ) must balance inner parens. lua's luaL_newlibtable idiom
   sizeof(l)/sizeof((l)[0]). Exit 42. */
struct KV { const char *n; int v; };
static struct KV tbl[] = { {"a",1}, {"b",2}, {"c",3} };
int main(void) {
  unsigned a = (unsigned)sizeof((tbl)[0]);   /* parse must not cascade */
  unsigned b = (unsigned)sizeof(int);
  (void)a; (void)b;
  return 42;
}
