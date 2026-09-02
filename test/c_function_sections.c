/* `--function-sections` under --emit-obj: an internal call becomes a RELOCATION
 * against the callee's own FUNC symbol instead of a displacement baked at emit
 * time by ApplyCallFixups.
 *
 * WHY IT MATTERS (feature-a-every-emit-obj-object-links-its-own-full-copy-of-crtl):
 * measured, an object's .rela.text already holds 1699 entries for a file this
 * size and every one targets DATA -- .bss, .data, errno, optind, opterr -- while
 * ZERO target a FUNC. That is why N objects cost N runtimes: the linker cannot
 * drop or share code it cannot re-aim, because user code jumps at a
 * displacement computed for its OWN copy of the runtime.
 *
 * THIS STEP HAS NO OBSERVABLE EFFECT ON ITS OWN, and that is precisely what the
 * Makefile rows assert: with one .text section the linker must compute exactly
 * the displacement that was baked, so the LINKED BINARY IS BYTE-IDENTICAL with
 * the flag on and off. A step that changes nothing can only be verified by
 * proving it changed nothing -- paired with a control proving the two OBJECTS
 * really do differ, or "identical" would just mean the flag did not run.
 *
 * The rows compile to ONE object path and link each before overwriting it. That
 * is load-bearing, not tidiness: gcc records the input object's name as an
 * STT_FILE symbol, so two objects called off.o and on.o produce binaries that
 * differ in .strtab by the one character of their names and in 10755 bytes
 * downstream of it. Measured, chased, and it is the instrument -- .text, .data
 * and .rodata were byte-identical the whole time.
 *
 * A four-deep chain plus a static, so the object holds internal calls of both
 * bindings (a static is a LOCAL symbol, an extern one GLOBAL, and the two take
 * different arms of ObjPlanHostedProcSymIdx). */
#include <stdio.h>

static int deep3(int x) { return x + 1; }
int deep2(int x) { return deep3(x) * 2; }
int deep1(int x) { return deep2(x) + 3; }

int main(void) {
  printf("%d\n", deep1(4));
  return 0;
}
