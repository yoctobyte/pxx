/* A cast to a type name that was never declared must be an ERROR, and the
   message must name the type and suggest the near miss.

   Before the fix cfront fell through to the undeclared-identifier-as-value
   leniency, so `(_PyCFunctionFastWithKeywords)f` became the integer 0 — a NULL
   function pointer stored in a method table, crashing far from the cast. Found
   in cpyext M5 on Cython-generated C, where the private pre-3.13 spelling of
   the typedef differs from the declared one by a single leading underscore.
   bug-cfront-undeclared-type-in-cast-treated-as-zero */

typedef int (*PyCFunctionFastWithKeywords)(int);

static int f(int x) { return x + 1; }

struct M { PyCFunctionFastWithKeywords fp; };

static struct M tab = { (_PyCFunctionFastWithKeywords)f };

int main(void) { return tab.fp(41); }
