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
 * FOUR directions are asserted across five rows, and each of the last two is a
 * successive attempt at this fix getting it wrong in the OPPOSITE direction
 * from the one before. crtl must use its own ctype (rows 1-2); the program must
 * still get its own macro in its own code (row 3); a FEATURE-TEST macro must
 * still reach the shared headers even from inside a crtl pull (row 4); and
 * crtl's OWN header macros must reach its OWN impl (row 5).
 *
 * Row 4: hiding _GNU_SOURCE too made crtl's <string.h> skip its forward to
 * <strings.h>, and because that header is include-guarded the narrower decision
 * became PERMANENT -- the program's own later #include expanded to nothing and
 * strncasecmp was undeclared in the PROGRAM, two steps away from the change.
 * A fix that hides the program's macros too far passes rows 1-3 alone.
 *
 * Row 5: hiding by macro INDEX cannot tell crtl's macros from the program's,
 * because the program's #include of a crtl header is what defines them and the
 * index lands in the hidden range either way. ORIGIN is the discriminator, not
 * index and not spelling -- the name-based rule that makes row 4 pass gets row
 * 5 wrong (RLIM_INFINITY has no leading underscore) and vice versa, so both
 * rules are live and neither subsumes the other.
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

/* Row 5's setup, and the ORDER is again the whole point. Including this HERE,
   from the program, is what puts RLIM_INFINITY inside the hidden window: the
   window is "every macro defined after the command-line -D", and a macro does
   not stop being crtl's because the program's #include is what caused it to be
   defined. sys/resource.c's own `#include <sys/resource.h>' re-resolves to a
   guarded, empty header, so the impl never gets a second chance to see it. */
#include <sys/resource.h>

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
  /* 5: the OPPOSITE direction from rows 1-2. Those assert the program's macros
        do NOT reach crtl; this asserts crtl's OWN header macros DO. A fix that
        hides by macro INDEX alone passes rows 1-4 and fails here, because
        RLIM_INFINITY was defined while the program was including a crtl header
        and so lands in the hidden range with everything else.
        Measured before the fix: `narrow()' saw RLIM_INFINITY as 0 (the
        frontend warned "undeclared identifier ... treated as 0" pointing INSIDE
        sys/resource.c), so `if (v >= 0) return RLIM_INFINITY;' returned 0 for
        every limit and RLIMIT_NOFILE came back as zero. Hence >0, not just
        rc==0: the bug returned success with a nonsense value. */
  {
    struct rlimit rl;
    int ok = getrlimit(RLIMIT_NOFILE, &rl) == 0 && rl.rlim_max > 0;
    printf("crtlmacro %d\n", ok);
  }
  return 42;
}
