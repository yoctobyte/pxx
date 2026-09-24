/* A declarator NAME in redundant parentheses: `T *(name[N]) = {...}`.

   sqlite's shell.c declares its help table `static const char *(azHelp[])`.
   The file-scope dispatcher saw the '(' and routed the declaration to the
   FUNCTION parser, which found no name and skipped it to the ';' -- the
   initializer with it -- so every use was "undeclared identifier". The
   function-scope parser broke out of its declarator loop on the same '('.

   Rows: the sqlite shape; a 2-D array; a scalar and an array in one
   declaration; `(g)[3]`, where the dims follow the parens; lua.h's
   `(name)(params)` function style, which must stay a function; and the
   function-scope spelling. Values are gcc's. */
#include <stdio.h>
static const char *(g1[]) = { "x", "y", "z" };
int (g2[2][3]) = { {1, 2, 3}, {4, 5, 6} };
int (g3) = 7, (g4[2]) = {8, 9};
int (g5)[3] = {10, 11, 12};
static int (twice)(int v);
static int (twice)(int v) { return 2 * v; }
int main(void) {
  const char *(l1[]) = { "p", "q" };
  printf("%s %d %d %d %d %d %d %s %d\n", g1[2], (int)(sizeof(g1)/sizeof(g1[0])), g2[1][2], g3, g4[1], g5[2], twice(21), l1[1], (int)sizeof(g5));
  return 0;
}
