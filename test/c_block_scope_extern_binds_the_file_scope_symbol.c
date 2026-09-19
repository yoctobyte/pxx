/* `extern` INSIDE A FUNCTION BODY was not a declaration opener at all: the
   block-scope storage-class loop in ParseCStatementAST did not accept it, so
   the statement parser fell through to expression parsing and legal C was
   refused with `undeclared identifier 'extern' used as value` -- a diagnostic
   naming the wrong token entirely.
   bug-c-a-block-scope-extern-declaration-is-parsed-as-an-expression-and-refused

   THESE ROWS ASSERT BINDING, NOT COMPILATION, AND THAT IS THE WHOLE POINT.
   The obvious fix -- add `extern` to the loop set and stop -- makes the
   declaration fall into the ordinary local-declaration arm, which ALLOCATES A
   STACK SLOT. The name then shadows the file-scope symbol it was written to
   reach, and the program compiles cleanly and returns the wrong number:
   measured 2026-09-19 on exactly the first row below, pxx printed -80651752
   where gcc prints 7. A fixture that checked only "it compiles now" passes that
   regression and certifies a silent wrong value in place of a loud refusal.

   EVERY ROW WRITES THROUGH THE EXTERN NAME AND READS BACK BY ANOTHER ROUTE,
   through a function with no `extern` anywhere in it. Reading alone is not
   enough: a shadowing local is UNINITIALISED, so it can hold the right value by
   luck and the row goes green on the broken compiler. A write that the other
   route cannot see is the thing a local physically cannot fake.

   Measured against gcc on this same source, 2026-09-19: both print the line at
   the bottom. */
#include <stdio.h>

int g = 7;
int a = 11;
int b = 13;

/* No `extern` in any of these -- they are the second route. */
static int peek_g(void) { return g; }
static int peek_a(void) { return a; }
static int peek_b(void) { return b; }

int main(void)
{
  int fails = 0;
  int reached;

  {
    /* Row 1: the object form. Read must see the file-scope initialiser... */
    extern int g;
    if (g != 7)
      { printf("FAIL read: block-scope extern int g read %d (want 7)\n", g); fails++; }
    /* ...and the write must land in the file-scope object, not in a local. */
    g = 42;
  }
  if (peek_g() != 42)
    { printf("FAIL bind: wrote 42 through extern, file scope still %d\n", peek_g()); fails++; }

  {
    /* Row 2: more than one declarator on one `extern`. The declaration is
       discarded as a unit, so a skip that stopped at the first comma would
       leave `b;` behind as a statement and bind only `a`. */
    extern int a, b;
    a = 21;
    b = 23;
  }
  if (peek_a() != 21 || peek_b() != 23)
    { printf("FAIL multi: wrote 21/23, file scope has %d/%d\n", peek_a(), peek_b()); fails++; }

  {
    /* Row 3: the FUNCTION form, and the callee is deliberately defined BELOW
       main with no earlier declaration -- naming one symbol without pulling in
       a header is the reason this construct is written at all. */
    extern int add2(int x, int y);
    if (add2(2, 3) != 5)
      { printf("FAIL fn: block-scope extern fn returned %d (want 5)\n", add2(2, 3)); fails++; }
  }

  {
    /* Row 4: a declarator carrying its own parentheses and brackets. A skip
       that scanned for the next `;` without tracking depth would be fine here
       but not on the array-of-pointers row below it; both are present so the
       row fails if the skip ever stops being depth-aware. The statement AFTER
       them is what proves the skip ended in the right place -- if it ran on,
       `reached` keeps its old value and the row fires. */
    extern int (*fp)(int x, int y);
    extern int (*tbl[4])(int x);
    reached = 0;
    reached = 99;
    if (reached != 99)
      { printf("FAIL depth: skip ran past the declaration\n"); fails++; }
  }

  if (!fails) printf("block-scope extern binds the file-scope symbol: 5 rows OK\n");
  return fails != 0;
}

int add2(int x, int y) { return x + y; }
