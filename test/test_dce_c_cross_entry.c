/* The C entry stub's calls, on a target whose branch is not a rel32.
 *
 * WHAT THIS IS FOR. PatchEntryStubCall patches the stub's forward call to
 * `main` by hand, and on four targets out of five it never RECORDED that site.
 * RecordEntryRoot kept the callee alive; nothing re-aimed the caller. So --dce
 * dropped the crtl bodies sitting between the stub and `main`, everything
 * after the hole slid down, and the stub still branched at the old address --
 * measured on aarch64 as a `bl` carrying imm26 0x1d4d4 to 0x475488, which is
 * inside the PRE-dce code segment and past the top of the shrunken one.
 * SIGSEGV before the first syscall, on every cross target, since 2026-08-21.
 *
 * TWO CALL SITES, NOT ONE, and this fixture reaches both:
 *   - the call to `main`, always emitted
 *   - the call to `__pxx_run_initializers`, emitted only when the source
 *     mentions `environ` (CNeedsEnvironInit is a token scan). Both were
 *     patched by the same unrecorded routine and both were measured broken.
 *
 * WHY NO PASCAL FIXTURE EVER CAUGHT IT: pasparser does not call
 * PatchEntryStubCall at all, and the Rust, Zig and Erlang drivers refuse every
 * non-x86-64 target. C is the only frontend that reaches a cross arm here, and
 * the x86-64 arm was the one with the record -- so the entire covered
 * population was the single case that worked.
 *
 * 1729 is deliberate: not 0, not 1, not a length, not a pointer width, and not
 * anything a zeroed or untouched word would produce. A `return 0` shell and a
 * dropped body both print something else. */
#include <stdio.h>

extern char **environ;

static int taxicab(int a, int b)
{
    return a * a * a + b * b * b;
}

static int env_present(void)
{
    char **p = environ;
    return (p != 0 && *p != 0) ? 1 : 0;
}

int main(void)
{
    /* 1^3 + 12^3 == 9^3 + 10^3 == 1729 */
    printf("dce-c-cross %d %d %d\n",
           taxicab(1, 12), taxicab(9, 10), env_present());
    return 0;
}
