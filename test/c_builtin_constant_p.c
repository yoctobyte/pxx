/* `__builtin_constant_p(x)` reduces to 0 UNCONDITIONALLY here (5cc4af7da),
   where gcc answers 1 when x folds at compile time. That is a DELIBERATE
   divergence and it is the conservative direction: 0 selects the generic arm,
   which computes the same value the constant arm would. Every row below is a
   property PXX guarantees; row 1 is the one gcc disagrees with, and a
   gcc_diff_probe on this file is EXPECTED to differ there.

   Why this file exists rather than the five gtk tests that the reduction
   turned green: measured 2026-09-02, forcing the reduction to 1 and rebuilding
   leaves all five byte-identical in output. They prove the builtin is
   RECOGNISED -- they were failing to COMPILE before it existed -- and they say
   nothing whatever about the VALUE. A green that would be green either way is
   not evidence about the value, and the same trap caught the lua suite, which
   passes 6/6 with the jump-table interpreter compiled out.

   Row 5 is the load-bearing one and it is about EMISSION, not about a runtime
   branch. glib and busybox both write `if (__builtin_constant_p(x) && <cond>)
   <special>;`, and the special arm calls things that may not be linked in.
   With the reduction at 0 the `&&` folds and the arm's call is never emitted.
   `never_linked` below is declared and defined nowhere at all, so it can only
   resolve while the fold holds -- that is exactly the busybox
   `data_extract_to_command` shape, which was the last undefined symbol in that
   link. Measured as a positive control 2026-09-02: with the reduction forced
   to 1 and the compiler rebuilt, pxx does NOT refuse the link. It warns
   (`crtl does not define never_linked -- this C program will import them from
   the system C library at run time`), produces a binary, and the program dies
   with `symbol lookup error: undefined symbol: never_linked`, rc 127. So the
   row discriminates -- 127 against 42 -- but the tell is a runtime loader
   error and a compile-time warning, never a link failure. Do not wait for a
   link error that this toolchain does not produce.

   Exit 42. */

extern int never_linked(int);      /* declared here, defined nowhere at all */

static int side_effects = 0;
static int bump(void) { side_effects = 1; return 7; }
static int gen(int x) { return x * 10; }

#define pick(x) (__builtin_constant_p(x) ? (x) * 10 : gen(x))

static int guarded(int x) {
  /* row 5: the arm must DISAPPEAR, not merely be skipped at runtime */
  if (__builtin_constant_p(x) && x > 0) return never_linked(x);
  return x + 1;
}

int main(void) {
  int v = 3;
  int fails = 0;

  /* 1. a literal argument. gcc says 1; we say 0, by design. */
  if (__builtin_constant_p(5) != 0) fails |= 1;

  /* 2. a runtime value. gcc agrees: 0. */
  if (__builtin_constant_p(v) != 0) fails |= 2;

  /* 3. the operand is UNEVALUATED -- gcc guarantees this too, and glib relies
        on it in `__builtin_constant_p (strlen (str))`. */
  if (__builtin_constant_p(bump()) != 0) fails |= 4;
  if (side_effects != 0) fails |= 8;

  /* 4. soundness: whichever arm the reduction selects, the ANSWER is right. */
  if (pick(v) != 30) fails |= 16;
  if (pick(4) != 40) fails |= 32;

  /* 5. see the header -- if the fold stops holding this file stops LINKING,
        so reaching main at all is half the assertion; the value is the rest. */
  if (guarded(9) != 10) fails |= 64;

  /* 6. usable where a constant expression is required. */
  {
    int arr[__builtin_constant_p(v) + 1];   /* length 1 */
    arr[0] = 5;
    if (arr[0] != 5) fails |= 128;
  }

  return fails ? fails : 42;
}
