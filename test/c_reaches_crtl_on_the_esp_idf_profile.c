/* C that REACHES CRTL, on an ESP target. The point is the #include and the
 * printf, not the output: this is an --emit-obj row, so nothing here runs.
 *
 * `#include <stdio.h>` plus a printf stopped with
 * `compiler error: PXXMemZero not found` under --target=xtensa --emit-obj,
 * while the same source built with --platform=posix as an object AND as an
 * executable. PXXMemZero is defined unconditionally in builtinheap.pas, so the
 * symbol existed and the unit was simply never pulled in.
 *
 * The gate was spelled `TargetPlatform <> PLATFORM_ESP` where the rest of the
 * compiler asks `TargetIsEspClass`. The two agree on riscv32 and differ on
 * xtensa, which is PLATFORM_ESP UNCONDITIONALLY -- so the gate was permanently
 * False there and no xtensa C source could reach crtl on ANY profile, which
 * contradicted both its own block comment and the Pascal driver's 24 sites.
 * bug-s-c-on-the-esp-profile-cannot-reach-crtl
 *
 * WHAT THE ROWS AROUND THIS FILE PIN, AND WHY THE SECOND ONE MATTERS MOST
 * ----------------------------------------------------------------------
 * The IDF profiles must BUILD this, and the resulting object must carry
 * PXXMemZero as a DEFINED symbol -- asserted separately, because "the compiler
 * accepted it" and "the helper is actually in the object" are two claims and
 * only the second is the one that was broken.
 *
 * The BARE profile must still REFUSE it. Bare metal deliberately gets no
 * default RTL, so a fix that made every profile build this would have widened
 * the contract rather than corrected the predicate -- and that widening is
 * invisible in a suite that only checks the targets it wants to work.
 *
 * KNOWN AND NOT FIXED HERE: on bare the refusal is still spelled as an
 * internal assertion with no remedy a C programmer could act on (there is no
 * `uses` clause in C). That is the remaining half of the ticket, and it is the
 * diagnostic, not the contract -- so the bare row below greps for the SYMBOL
 * NAME rather than the full wording, and is expected to change when that half
 * lands.
 */

#include <stdio.h>

int main(void)
{
    printf("hello\n");
    return 0;
}
