/* A header that DEFINES functions, which is ordinary C: `static` and
   `static inline` have internal linkage, so the definition is the header and
   there is no library to import them from.

   The `uses <header>` path assumed a header "declares and defines nothing",
   dropped these bodies, marked them external, and synthesised a soname from
   the header's own stem -- so calling one produced a binary with a DT_NEEDED
   on lib<header>.so that could not be loaded.
   bug-c-a-header-reached-by-uses-discards-function-bodies-and-imports-them-instead */
static int hs_plain(void) { return 4242; }
static inline int hs_inline(int v) { return v + 1; }

/* ...beside a bodied static that is never called. This one was always
   harmless -- no call, no import -- and must stay harmless. */
static inline int hs_unused(void) { return -1; }

/* ...and a bare DECLARATION, which is the FFI surface the header path exists
   for and must keep its old treatment. Not called here: calling it would ask
   for libhdrstatic.so, which is the design, not the bug. */
int hs_declared_only(int x);
