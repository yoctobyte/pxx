/* Regression: a parenthesized function name must still be callable — `(f)(args)`
   is a direct call, same as `f(args)`. This is the C `(gzgetc)(g)` idiom used in
   zlib's gzgetc macro fallback arm. Before the fix `(f)(x)` decayed f to its
   address and dropped the call, returning the address low byte. Also covers a
   self-referential function-like macro whose fallback re-parenthesizes its own
   name (blue-paint: not re-expanded). */

int add41(int g) { return g + 41; }

/* self-referential macro: the `(add)(g)` arm calls the real function, the macro
   name being painted blue inside its own expansion. Real def precedes the macro
   so the definition is not itself macro-expanded. */
int add(int g) { return g + 41; }
#define add(g) ((g) ? (add)(g) : 0)

int main(void) {
  if ((add41)(1) != 42) return 1;   /* parenthesized name, direct call */
  if (add(1) != 42) return 2;       /* macro fallback -> (add)(1) */
  if (add(0) != 0) return 3;        /* macro true-arm short path */
  return 42;
}
