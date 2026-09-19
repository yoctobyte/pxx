/* A thread-local declared INSIDE A FUNCTION BODY was the only member of the
   degraded-`__thread` family that said NOTHING AT ALL.
   bug-c-thread-local-storage-still-shares-one-copy-off-x86-64-and-a-warning-is-all-that-stands-there

   The other five shapes reach TryAssignThreadVarStorage and are refused for a
   named reason. This one never reaches it: the block-scope storage-class loop
   in ParseCStatementAST consumed `__thread` and recorded only `static`, so the
   qualifier was gone before a symbol existed. Not refused -- never asked.

   THIS FILE IS THE VALUE HALF, AND IT IS NOT VACUOUS. The warning must be
   delivered WITHOUT changing the storage, so these rows assert NON-CHANGE:
   `static __thread` still behaves as a block-scope static, which is what it did
   before the warning existed and what gcc does. A row that reads as asserting
   nothing is exactly the row someone "simplifies" away, and then the next
   change to this seam delivers a correct warning on top of broken storage and
   nothing notices. Measured 2026-09-19 against gcc on this same source: both
   print the line below.

   EVERY COUNTER IS READ MORE THAN ONCE, for the reason the sibling fixture
   c_block_static_survives_a_storage_class.c records: a discarded static and a
   real one agree on the FIRST call, which is how the dropped-`static` bug
   survived. The second call is what discriminates.

   TWO DECLARATIONS, DELIBERATELY. The warning is once-per-REASON, and a fixture
   with a single declaration cannot tell once-per-reason from once-per-
   compilation. This family exists because a one-shot flag reported a `__thread`
   array and suppressed a `__thread` struct entirely, so the arrangement that
   certifies that bug is the one-declaration arrangement. The Makefile row
   asserts the count is exactly 1 across BOTH of these. */
#include <stdio.h>

static int bump(void)   { static __thread int x; x++;    return x; }
static int bytwo(void)  { static __thread int y; y += 2; return y; }

int main(void)
{
  int fails = 0;
  /* Assigned to locals first and in statement order: argument evaluation order
     is unspecified, and gcc evaluates printf's arguments right to left, so
     calling these inside the call would read the counters backwards and look
     like a defect in the storage rather than in the fixture. */
  int a1 = bump();
  int a2 = bump();
  int a3 = bump();
  int b1 = bytwo();
  int b2 = bytwo();

  if (a1 != 1 || a2 != 2 || a3 != 3)
    { printf("FAIL bump: %d %d %d (want 1 2 3)\n", a1, a2, a3); fails++; }
  if (b1 != 2 || b2 != 4)
    { printf("FAIL bytwo: %d %d (want 2 4)\n", b1, b2); fails++; }

  /* Called again after the other counter has run: the two block-scope
     thread-locals must be INDEPENDENT objects. A single shared slot -- which is
     what a future "give these real storage" change could produce by handing
     both declarations the same area offset -- passes every row above and fails
     this one. */
  if (bump() != 4)  { printf("FAIL bump did not survive bytwo\n"); fails++; }
  if (bytwo() != 6) { printf("FAIL bytwo did not survive bump\n"); fails++; }

  if (!fails) printf("func-scope __thread: storage unchanged, 4 rows OK\n");
  return fails != 0;
}
