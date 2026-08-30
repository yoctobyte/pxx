/* An UNSIGNED constant guard must be decidable at compile time, like every
   other constant one. `PXX_NEVER_UNSIGNED_GUARD` is declared and defined
   nowhere, so if a dead arm survives, this binary does not START -- the
   assertion is that it runs at all, not that it prints a particular number.

   The shape is not exotic, it is the portable-C idiom: `UINT_MAX ==
   0xffffffff` and friends are how real code asks how wide a type is. busybox's
   include/xatonum.h is exactly this, and it declares
   BUG_xatou32_unimplemented() without ever defining it, on the assumption that
   the guard folds.

   WHY IT NEEDED ITS OWN FIX, once the constant-`if` fold already existed: the
   C frontend runs both operands of an unsigned 32-bit comparison through
   CTrunc32, which models the usual arithmetic conversions by masking each side
   to 32 bits. On a LITERAL that produced `(k & $FFFFFFFF) == (k & $FFFFFFFF)`
   -- two const-const BINOPs -- and no fold in the pipeline sees through those,
   so the comparison stayed a runtime question. `4 == 4` folded and `4u == 4u`
   did not. CTrunc32 now truncates a literal in the parser.

   The `sizeof` rows are the control in the other direction: they went through
   a different path and already worked, so a regression here is attributable.
   feature-c-corpus-busybox-applet */
#include <stdio.h>
#include <limits.h>

int PXX_NEVER_UNSIGNED_GUARD(void);

static int uint_max_eq(int x)   { if (UINT_MAX == 0xffffffff) return x + 1;
                                  return PXX_NEVER_UNSIGNED_GUARD(); }
static int u_suffix_eq(int x)   { if (4u == 4u) return x + 2;
                                  return PXX_NEVER_UNSIGNED_GUARD(); }
static int hex_vs_u(int x)      { if (0xffffffff == 4294967295u) return x + 3;
                                  return PXX_NEVER_UNSIGNED_GUARD(); }
static int u_suffix_ne(int x)   { if (4u != 5u) return x + 4;
                                  return PXX_NEVER_UNSIGNED_GUARD(); }
static int int_max_eq(int x)    { if (INT_MAX == 2147483647) return x + 5;
                                  return PXX_NEVER_UNSIGNED_GUARD(); }
static int sizeof_eq(int x)     { if (sizeof(unsigned) == 4) return x + 6;
                                  return PXX_NEVER_UNSIGNED_GUARD(); }

/* CONTROL: the same operators on a RUNTIME unsigned value. Both arms are
   reachable and both are exercised, because a fold that ate live code would
   otherwise look identical to one that works. */
static int runtime_u(unsigned u) { if (u == 4u) return 100; return 200; }

int main(void)
{
  printf("%d\n", uint_max_eq(10));
  printf("%d\n", u_suffix_eq(10));
  printf("%d\n", hex_vs_u(10));
  printf("%d\n", u_suffix_ne(10));
  printf("%d\n", int_max_eq(10));
  printf("%d\n", sizeof_eq(10));
  printf("%d\n", runtime_u(4));
  printf("%d\n", runtime_u(5));
  return 0;
}
