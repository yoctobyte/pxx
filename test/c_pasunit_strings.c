/* The C half of cpasunit_strings.pas. Prints exactly what
   test_c_pasunit_strings.pas prints from the same unit — the Makefile asserts
   the two outputs are byte-identical, so the ORACLE is the Pascal driver
   compiling the very same source, not a hand-written expectation.
   bug-a-c-driver-omits-rtl-stubs-for-an-imported-pascal-unit */
#include "cpasunit_strings.pas"
extern int printf(const char *, ...);

int main(void) {
  char buf[64];
  int i;
  printf("lit=%d\n", cpasunit_strings_pas_LitLen());
  printf("varlit=%d\n", cpasunit_strings_pas_ConcatVarLit());
  printf("litvar=%d\n", cpasunit_strings_pas_ConcatLitVar());
  printf("varvar=%d\n", cpasunit_strings_pas_ConcatVarVar());
  printf("chain=%d\n", cpasunit_strings_pas_ConcatChain());
  for (i = 1; i <= 7; i++) printf("%d ", cpasunit_strings_pas_CharCodeAt(i));
  printf("\n");
  cpasunit_strings_pas_CopyTag(buf, sizeof buf);
  printf("tag=%s\n", buf);
  return 0;
}
