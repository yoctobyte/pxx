/* The C half of test_asm_in_unreachable_tail.pas, and a second ROUTE to the
   same defect rather than a restatement: the C frontend builds AN_ASM in
   CAsmBuildBlock and reaches ASTSubtreeHasLabel through the AN_BLOCK cons
   walk, not the AN_SEQ spine.

   AN_ASM's ASTLeft/ASTRight are an AsmBytes offset and length, not node
   references. Recursing into them returned a spurious True -- "there is an
   entry point behind this terminator" -- which suppressed the prune, so the
   call to the undefined never_asmprobe_c was emitted and the binary would
   not start. Asserting a RUN is therefore the assertion that can fail. */
#include <stdio.h>
extern int never_asmprobe_c(void);
int g;
static void after_return_with_asm(void) {
  g++;
  return;
  __asm__("nop");
  g = never_asmprobe_c();
}
int main(void) { g = 0; after_return_with_asm(); printf("ASM TAIL OK g=%d\n", g); return 0; }
