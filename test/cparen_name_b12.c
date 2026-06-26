/* Parenthesized declarator name in a prototype: `int (f)(int);` — lua.h declares
   its whole API this way (`LUA_API int (lua_gettop)(lua_State *L);`). Exit 30. */
extern int (add) (int a, int b);          /* prototype, parenthesized name */
const char *(pick) (const char *s);       /* pointer return + paren name */
int add(int a, int b) { return a + b; }
const char *pick(const char *s) { return s; }
int main(void) {
  int r = add(12, 18);                     /* 30 */
  const char *p = pick("x");
  return r + (p[0] == 'x' ? 0 : 99);       /* 30 */
}
