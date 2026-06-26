# C: large (>16-byte) record passed by value gives garbage in the callee

- **Type:** bug (Track C / shared codegen)
- **Found:** 2026-06-26 while finishing C varargs.

A small record by-value param works (`struct {int a;}` -> 42). A 24-byte record
(`struct B {long a,b,c;}`) passed by value reads garbage in the callee:
`int g(struct B s){return (int)s.b;}` with `s.b=42` returns 200.

Repro:
```c
struct B { long a, b, c; };
int g(struct B s) { return (int)s.b; }      /* want 42, gets 200 */
int main(void){ struct B x; x.a=1; x.b=42; x.c=3; return g(x); }
```

Impact: blocks C-varargs **va_list passing** (lua's luaL_error ->
lua_pushvfstring(L, fmt, argp) hands a 24-byte va_list by value). Local va_arg
(int/long/ptr/string) already works; only passing the va_list to another function
hits this. Likely the by-value copy / SysV register-vs-stack classification for
records >16 bytes in the C call path.
