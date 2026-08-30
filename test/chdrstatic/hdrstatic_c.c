/* The identical functions in a .c unit. The whole point of the pair: the same
   source text must behave the same whichever extension it is given. */
static int hs_plain(void) { return 4242; }
static inline int hs_inline(int v) { return v + 1; }
