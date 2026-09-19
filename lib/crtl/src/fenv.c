/* SPDX-License-Identifier: MPL-2.0 */
/* C99 fenv rounding-mode primitives, for the target that cannot have the
 * compiler's machine-code ones.
 *
 * EVERYWHERE ELSE THESE ARE EMITTED, NOT COMPILED. `EmitCFenvStubs` in
 * cparser.inc writes __pxx_fesetround/__pxx_fegetround as raw bytes: x86-64
 * flips the MXCSR RC bits (pxx does all double arithmetic in SSE, so MXCSR is
 * the only rounding state that matters), and every other target gets
 * `return 0` through EmitCReturnZeroStub. wasm32 has no machine code for that
 * emitter to write, so it was skipped -- and the symbol then reached the
 * module as an unresolved import, which is where a hosted C program on wasm32
 * stopped once the encoder ceiling behind it was lifted.
 *
 * WHY THE SKIP BUNDLED IT WITH setjmp, AND WHY THAT WAS WRONG. One guard
 * covered both emitters for one stated reason -- they emit raw machine code --
 * and the reason is true of both while the CONSEQUENCE is not. setjmp cannot
 * be made correct on wasm at all: a module's call stack is not addressable
 * memory, so there is nothing for longjmp to unwind across, and a stub that
 * quietly answers 0 every time is a program whose error path never runs.
 * fegetround is the opposite case -- the answer is not merely available, it is
 * EXACT. wasm's f32/f64 arithmetic is round-to-nearest-ties-to-even and there
 * is no instruction to change it, so FE_TONEAREST is not a placeholder, it is
 * the truth about the machine. The impossible half was hiding a half with a
 * correct trivial answer.
 *
 * AND THE TWO HALVES DIFFER FROM EACH OTHER, which is the part that would be
 * lost by copying EmitCReturnZeroStub's `return 0` here. A getter can tell the
 * truth; a SETTER cannot, because there is nothing to set. C says fesetround
 * returns zero if and only if the mode was established, so it answers nonzero
 * for anything but FE_TONEAREST rather than reporting a success that did not
 * happen. That is a deliberate divergence from arm32/riscv32/xtensa, whose
 * `return 0` is a placeholder for a rounding mode those machines really do
 * have and we have not wired up -- unimplemented, where this is unsupportable.
 * A caller that checks the return (quickjs's js_dtoa rides fesetround) gets a
 * usable answer here and a false one there.
 *
 * Pulled because <fenv.h> is included by src/stdio.c, whose float formatter is
 * the one crtl caller; on every other target this file preprocesses to nothing
 * and the emitter's stubs stand.
 * bug-c-hosted-c-on-wasm32-needs-environ-and-va-arg-so-stdio-programs-still-refuse
 */
#include <fenv.h>

#if defined(__wasm__)

int __pxx_fegetround(void)
{
	return FE_TONEAREST;
}

int __pxx_fesetround(int mode)
{
	if (mode == FE_TONEAREST) return 0;
	return -1;
}

#endif
