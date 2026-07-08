/* Regression (bug-c-anon-struct-nested-enum-global): an inline `enum {...}` body
 * in type position — a struct member, a typedef, or a global var — must be
 * consumed AND register its enumerators. Before, ParseCDeclType skipped only the
 * `enum` keyword + tag, leaving `{...}` for the declarator reader (stray-token
 * error on `struct { enum{X} x; } s;`) and folding enumerators to 0. Returns 42
 * = C(2) + Q(1) + Z(7) + sizeof(v)(8) + 24. */
struct { enum { A, B, C } x; int y; } v;   /* nested anon enum member + declarator */
typedef struct { enum { P, Q } x; } T;     /* nested anon enum in a typedef */
enum { Z = 7 } zz;                          /* plain enum global with a declarator */
int main(void) {
  return C + Q + Z + (int)sizeof(v) + 24;
}
