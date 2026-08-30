/* The other half of the pair: identical to hdrstatic.h's two called functions,
   as a `.c`. This half always worked -- it is the control that says the `.h`
   half's failure was about the extension and nothing else. */
static int hs_plain(void) { return 4242; }

static inline int hs_inline(int v) { return v + 1; }
