/* A constant LEFT operand of `&&` or `||` must decide the operator at compile
   time. `PXX_NEVER_SHORT_CIRCUIT` is declared and defined nowhere, so if the
   dropped operand survives, this binary does not START -- the assertion is
   that it runs at all, not that it prints a particular number.

   The shape is not exotic and it is not the constant-`if` one already covered
   by c_const_branch_dead_arm.c. It is how a C project spells configuration:
   busybox's autoconf.h emits `#define ENABLE_FEATURE_INSTALLER 0`, and
   libbb/appletlib.c then writes

       if (ENABLE_FEATURE_INSTALLER && strcmp(argv[1], "--install") == 0) {
               busybox = xmalloc_readlink(...);

   with xmalloc_readlink not linked in at all in that configuration, and

       if (ENABLE_FEATURE_SH_STANDALONE || ENABLE_FEATURE_PREFER_APPLETS || !BB_MMU)
               if (NUM_APPLETS > 1) { if (re_execed_comm()) ... }

   with re_execed_comm likewise absent. gcc at -O0 and tcc (which has no
   optimiser at all) both fold these, so this is LOWERING and not an
   optimisation -- which is why every row here must hold at every -O level.

   WHY IT NEEDED ITS OWN FIX, once the constant-`if` fold already existed: the
   `&&`/`||` lowering materialises its result in a boolean temp and the branch
   RELOADS it, so IROptConstBranch -- which reads the operand feeding the jump
   -- saw a load_sym and gave up. The condition therefore survived EVERY -O
   level including -O3, unlike the `if (0)` shape, which -O1 already folded.
   The fold now happens in the C frontend where the node is built.

   The CHAIN row is not redundant with the single-operator rows. `||` is
   left-associative, so the first `||` hands its result to the second as an
   OPERAND; folding only at the operator and not also in CMakeTruthy leaves an
   unfolded `(0 != 0)` there and the chain stops one step in. That is busybox's
   actual three-term guard.

   The runtime rows are the control in the other direction: the same operators
   on values the compiler cannot know, with the evaluation COUNT checked, so a
   fold that ate live code or dropped a live side effect cannot pass.

   WHICH ROWS HOLD AT WHICH LEVEL, because the two halves are different work
   and reading this file as uniform would misroute the next person. Rows 11 and
   12 put the undefined call in the operand the fold DROPS, so the reference
   never reaches the IR and they hold at every level including -O0. Rows 13, 14
   and 15 put it in the ARM of an `if` whose condition this fold reduces to a
   literal -- the condition is decided everywhere, but pruning the now-dead arm
   is IROptDeadCode, which is gated at -O1, so at -O0 those three still die
   before main. That gate is not this ticket's: it is
   feature-a-fold-the-consensus-dead-branch-core-at-every-level, which exists
   to move the consensus core into lowering. This file is built at the default
   level like every other test here; when that ticket lands, it will pass at
   -O0 too, and THAT is the check to add there rather than here.
   feature-c-corpus-busybox-multi-applet */
#include <stdio.h>

int PXX_NEVER_SHORT_CIRCUIT(void);

#define OFF 0
#define ON  1
#define MMU 1

static int and_lit_false(int x) { if (OFF && PXX_NEVER_SHORT_CIRCUIT()) return -1;
                                  return x + 1; }
static int or_lit_true(int x)   { if (ON || PXX_NEVER_SHORT_CIRCUIT()) return x + 2;
                                  return -1; }
static int chain(int x)         { if (OFF || OFF || !MMU) return PXX_NEVER_SHORT_CIRCUIT();
                                  return x + 3; }
static int not_lit(int x)       { if (!ON) return PXX_NEVER_SHORT_CIRCUIT();
                                  return x + 4; }
static int nested(int x)        { if (OFF && (PXX_NEVER_SHORT_CIRCUIT() == 0)) {
                                    return PXX_NEVER_SHORT_CIRCUIT(); }
                                  return x + 5; }

/* CONTROL, and it is two claims, not one: the operators still BRANCH on a
   runtime value, and they still evaluate the right operand exactly when C says
   they must. A fold that dropped a live call would pass a value-only check. */
static int calls;
static int f(int v) { calls++; return v; }

static void control(const char *tag, int got, int want_calls)
{
  printf("%s %d calls=%d\n", tag, got, want_calls == calls ? calls : -calls);
}

int main(void)
{
  printf("%d\n", and_lit_false(10));
  printf("%d\n", or_lit_true(10));
  printf("%d\n", chain(10));
  printf("%d\n", not_lit(10));
  printf("%d\n", nested(10));

  calls = 0; control("lit0&&", 0 && f(1), 0);   /* not evaluated */
  calls = 0; control("lit1&&", 1 && f(7), 1);   /* evaluated, result 1 */
  calls = 0; control("lit1||", 1 || f(1), 0);   /* not evaluated */
  calls = 0; control("lit0||", 0 || f(9), 1);   /* evaluated, result 1 */
  calls = 0; control("run&&0", f(1) && 0,  1);  /* left is live */
  calls = 0; control("run||1", f(0) || 1,  1);  /* left is live */
  return 0;
}
