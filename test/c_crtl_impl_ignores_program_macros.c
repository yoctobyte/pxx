/* crtl's OWN implementation must not be preprocessed in the program's macro
 * environment.
 *
 * A libc shipped as source is still a separate translation unit. A real
 * toolchain's libc is immune by construction -- it is already compiled -- so
 * this is a hazard that exists only for a source-distributed runtime, and it is
 * invisible until a program redefines a name crtl itself uses.
 *
 * busybox does exactly that: include/libbb.h #undefs the whole ctype family and
 * redefines it, two members as deliberate poison
 * (`#define isprint(a) isprint_is_ambiguous_dont_use(a)`). That macro reached
 * lib/crtl/src/fnmatch.c's own isprint call and the build failed with
 * "call to undeclared function: isprint_is_ambiguous_dont_use" pointing INSIDE
 * crtl. Found building busybox's ash for rung 2.
 *
 * ORDER IS THE WHOLE BUG and is why this test defines before including. The
 * impl is auto-pulled when its header is included, so a program that includes
 * <fnmatch.h> BEFORE poisoning is unaffected -- which is the first shape I
 * tried, and it passed. Reversing the two lines is what reproduces it.
 *
 * THREE directions are asserted, and the third is the one the first attempt at
 * this fix got wrong. crtl must use its own ctype (rows 1-2); the program must
 * still get its own macro in its own code (row 3); and a FEATURE-TEST macro
 * must still reach the shared headers even from inside a crtl pull (row 4).
 * Hiding _GNU_SOURCE too made crtl's <string.h> skip its forward to
 * <strings.h>, and because that header is include-guarded the narrower decision
 * became PERMANENT -- the program's own later #include expanded to nothing and
 * strncasecmp was undeclared in the PROGRAM, two steps away from the change.
 * A fix that hides the program's macros too far passes rows 1-3 alone.
 *
 * NO GCC ORACLE, deliberately. This asserts a property only a libc distributed
 * as SOURCE can have or lose; gcc's libc is already compiled and cannot be
 * affected by the program's macros, so there is nothing to compare against.
 * gcc will not even build this file -- glibc declares isdigit as a function, so
 * the program's redefinition of it is a hard error there. That is a difference
 * in libc header shape, not a disagreement about behaviour.
 */
/* busybox sets this BEFORE any header; it must stay visible to crtl because it
   selects which API the SHARED headers expose, unlike the program's own macros
   below. The order matters here too -- a feature-test macro set after the
   header it gates does nothing, in any compiler. */
#define _GNU_SOURCE 1

#include <stdio.h>
#include <string.h>

/* Poison first, exactly as libbb.h does, THEN include. */
#undef isprint
#define isprint(a) isprint_is_ambiguous_dont_use(a)
#undef isdigit
#define isdigit(a) 12345

#include <fnmatch.h>
#include <ctype.h>

int main(void) {
  /* 1: crtl's fnmatch resolved [:print:] with crtl's isprint, not the poison. */
  printf("print %d\n", fnmatch("[[:print:]]", "x", 0) == 0);
  /* 2: and [:digit:] with crtl's isdigit, not the program's 12345. */
  printf("digit %d %d\n", fnmatch("[[:digit:]]", "5", 0) == 0,
                          fnmatch("[[:digit:]]", "x", 0) == 0);
  /* 3: the program's own macro is still the program's, in the program. */
  printf("mine %d\n", isdigit('5'));
  /* 4: _GNU_SOURCE still reached <string.h>, which forwards to <strings.h>.
        If a crtl pull got there first with the macro hidden, this is
        "call to undeclared function: strncasecmp". */
  printf("featuretest %d\n", strncasecmp("AB", "ab", 2) == 0);
  return 42;
}
