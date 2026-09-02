/* C99 6.10.3.1p1: a macro argument is fully macro-expanded before it is
 * substituted, unless it is an operand of # or ##. That applied to NAMED
 * parameters here and not to __VA_ARGS__, which was substituted raw on the
 * reasoning that the caller's rescan would expand it.
 *
 * The rescan does -- EXCEPT where the substituted text lands inside an
 * invocation of the macro's own name, which the rescan paints and copies
 * through verbatim. That is exactly the C idiom for wrapping a function in a
 * same-named macro, and busybox's miscutils/bc.c is built on it:
 *
 *     #define zbc_parse_stmt_allow_NLINE_before(...) \
 *         (zbc_parse_stmt_allow_NLINE_before(__VA_ARGS__) COMMA_SUCCESS)
 *
 * called as `..._before(STRING_if)' with `#define STRING_if (kws[9].name8)'.
 * STRING_if reached the parser unexpanded and the diagnostic was "undeclared
 * identifier passed as argument 1", pointing at a call site with nothing wrong
 * with it.
 *
 * Rows 1 and 3 are the broken shape. Rows 2 and 4 are the two spellings that
 * worked -- a named parameter, and the same body with the self-call written
 * `(name)(...)' so it is not an invocation of the name. They are the control:
 * they passed before the fix and they are the reason it reads as a busybox
 * oddity rather than a preprocessor gap until it is reduced.
 */
#include <stdio.h>

#define VAL 41

static int a1(int x) { return x + 1; }
static int a2(int x) { return x + 2; }
static int a3(int x) { return x + 3; }
static int a4(int x) { return x + 4; }
static int a5(int x, int y) { return x * 100 + y; }

#define a1(...) (a1(__VA_ARGS__) + 1000)      /* self-call, __VA_ARGS__ */
#define a2(x)   (a2(x) + 1000)                /* self-call, named param */
#define a3(...) (a3(__VA_ARGS__ ) + 1000)     /* space before ')' */
#define a4(...) ((a4)(__VA_ARGS__) + 1000)    /* parenthesised, not an invocation */
#define a5(...) (a5(__VA_ARGS__) + 1000)      /* several arguments, commas intact */

/* ## must still see the RAW argument: expanding first would paste VAL's
   replacement instead of the token `VAL'. A fix that pre-expands
   unconditionally passes every row above and fails this one. */
#define GLUE(p, ...) p ## __VA_ARGS__
#define xy 7

/* GNU `, ## __VA_ARGS__' with the variadic part omitted: the comma is deleted.
   Untouched by the change and here because it shares the code path. */
#define OPT(fmt, ...) printf(fmt, ## __VA_ARGS__)

int main(void)
{
  printf("1 %d\n", a1(VAL));
  printf("2 %d\n", a2(VAL));
  printf("3 %d\n", a3(VAL));
  printf("4 %d\n", a4(VAL));
  printf("5 %d\n", a5(VAL, VAL));
  printf("6 %d\n", GLUE(x, y));
  OPT("7 %d\n", VAL);
  OPT("8 no varargs\n");
  return 0;
}
