/* C99 6.7.4p7: which inline functions get an EXTERNAL definition in this
   translation unit. The Makefile row reads the object's symbol table:
   T = external definition, t = local copy (gcc emits nothing at all for the
   inline-only ones; pxx keeps a local body, which links the same way).
   bug-c-a-c99-inline-function-in-a-header-is-a-strong-symbol-in-every-object */
#include <stdio.h>

/* an inline definition and nothing else: no external definition -> t */
inline int only_inline(int x) { return x + 1; }

/* an inline definition with a later `extern` declaration: external -> T */
inline int later_extern(int x) { return x + 2; }
extern int later_extern(int x);

/* a non-inline prototype first: external -> T */
int proto_first(int x);
inline int proto_first(int x) { return x + 3; }

/* static inline: internal linkage -> t */
static inline int st_inl(int x) { return x + 4; }

/* extern inline (C99): the external definition -> T */
extern inline int ext_inl(int x) { return x + 5; }

/* gnu_inline reverses the rule: extern inline is inline-only -> t ... */
extern inline __attribute__((gnu_inline)) int gnu_ext(int x) { return x + 6; }

/* ... and a plain inline is the external definition -> T */
inline __attribute__((gnu_inline)) int gnu_plain(int x) { return x + 7; }

/* `__inline__` is the same keyword -> t */
__inline__ int dunder_inline(int x) { return x + 8; }

int main(void)
{
  printf("%d\n", only_inline(0) + later_extern(0) + proto_first(0) + st_inl(0) +
                 ext_inl(0) + gnu_ext(0) + gnu_plain(0) + dunder_inline(0));
  return 0;
}
