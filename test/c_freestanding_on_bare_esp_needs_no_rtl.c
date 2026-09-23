/* FREESTANDING C on the bare ESP profile: no crtl, no <stdio.h>, nothing that
 * needs the heap or the string runtime. This MUST BUILD, and it is the control
 * that constrains where the bare-profile refusal is allowed to live.
 *
 * bug-s-the-bare-esp-refusal-for-c-that-needs-the-rtl-is-an-internal-assertion
 * proposed raising that refusal beside cPullsBuiltinHeap in cparser.inc, where
 * the POLICY is decided. That gate cannot know the DEMAND: the pull is decided
 * once at parse time from tokens, while the need for a memzero is discovered at
 * CODEGEN when an aggregate or managed-record temp has to be zeroed, and no
 * token signals it -- unlike the softfloat pull a few lines below it, whose
 * demand really is a `float`/`double` token. So a refusal at that gate would
 * have had to be unconditional, and THIS FILE is what it would have broken.
 *
 * Freestanding bare C is the supported shape on --esp-profile=bare. The
 * refusal therefore lives at the one place demand is known --
 * FindHeapHelperOrRefuse in symtab.inc, which sixteen sites across six backends
 * now route through -- and it branches on whether policy explains the absence.
 *
 * Keep this file genuinely freestanding. Adding a printf, a malloc, or any
 * aggregate that needs zeroing turns it into the OTHER test (the one that must
 * be refused) and this row would then fail for the right reason in the wrong
 * place. */

int add(int a, int b) { return a + b; }
