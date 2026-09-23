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
 * THAT HALF LANDED 2026-09-24, and the foresight in the line below paid for
 * itself: the bare row greps for the SYMBOL NAME rather than the full wording,
 * so rewriting the message did not break it. What it also shows is why that row
 * was not enough on its own -- asserting only that bare REFUSES was satisfied by
 * the bad message too, so two rows now pin the message itself: it must name the
 * profile that excluded the unit, and it must NOT be spelled `compiler error:`,
 * which this tree reserves for internal faults. Both were verified to FAIL
 * against the old wording.
 *
 * The refusal lives in FindHeapHelperOrRefuse (symtab.inc), which fifteen
 * codegen sites across six backends now route through, and it BRANCHES on
 * whether policy explains the absence -- a profile exclusion gets an actionable
 * refusal, a genuinely missing builtinheap keeps the internal-fault spelling.
 * It is NOT at the cPullsBuiltinHeap gate its ticket proposed, because that gate
 * knows the policy and cannot know the demand; see
 * test/c_freestanding_on_bare_esp_needs_no_rtl.c, which is the row an
 * unconditional refusal there would have broken.
 * bug-s-the-bare-esp-refusal-for-c-that-needs-the-rtl-is-an-internal-assertion
 */

#include <stdio.h>

int main(void)
{
    printf("hello\n");
    return 0;
}
