/* b227: a function-like macro argument that is a string literal containing
   unbalanced parens/commas must not corrupt macro argument matching. Regression
   for the duktape wall `duk_push_literal(thr, "Symbol(")` — the '(' inside the
   string was counted as a real paren, breaking arg collection. */
#define PICK2(a, b) (b)
static int slen(const char *s) { int n = 0; while (s[n]) n++; return n; }
int main(void) {
  const char *s = PICK2(0, "Sym(bol,)");   /* ( ) , all live inside the string */
  return slen(s) == 9 ? 42 : 1;            /* "Sym(bol,)" is 9 chars */
}
