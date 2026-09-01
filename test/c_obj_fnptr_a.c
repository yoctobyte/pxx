/* Half A of the two-object CALLBACK-TABLE test.
   bug-a-c-a-global-initialised-with-a-function-address-is-not-exported

   A function-pointer global was the one file-scope form that got no OBJECT
   symbol at all -- not because of the initialiser, which is what the slug
   says, but because a fn-pointer declaration is registered by its own branch
   in cparser.inc that never recorded linkage. Six of seven forms exported and
   every fn-pointer form did not, on every target.

   The shape matters: this is the callback table. Another object referencing
   `Handler` linked cleanly against its own private .bss and read NULL, so the
   failure was a call through a null pointer far from the declaration. */
typedef int (*fp_t)(int);

static int dbl(int x) { return x * 2; }

fp_t Handler = dbl;

int call_handler(int v) { return Handler(v); }
