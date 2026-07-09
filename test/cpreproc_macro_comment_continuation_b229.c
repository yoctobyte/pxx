/* b229: a multi-line block comment whose lines end with backslash continuations,
   inside a #define body, must not truncate the macro. C translation phase 2
   (backslash-newline splicing) precedes phase 3 (comment removal), so every line
   of such a comment joins the logical #define line. Regression for duktape's
   refzero macros (DUK__RZ_SUPPRESS_CHECK), which desynced the do/while body. */
#define SETR(x) do { \
    /* explanatory comment line one \
     * comment line two \
     * comment line three */ \
    r = (x); \
  } while (0)
int main(void) {
  int r = 0;
  SETR(42);
  return r;   /* 42 iff the macro body was captured whole */
}
