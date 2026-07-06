
## Retry 2026-07-07 — reverted again, root cause pinned
Retried with a BETTER stride derivation (for `&base[i]`, stride =
IRPointerStride(base) via the reliable Syms element type, NOT ASTTk[inner] which
defaults to int for narrow arrays). This made 00037 pass AND standalone u16/char
`&a[i]-&a[j]` correct — but b133 STILL regressed (exit 2, `wp - wide != 204`).

Root cause pinned: `IRPointerStride` on an AN_ADDR node is called in TWO
contexts with conflicting needs:
1. ptrdiff `&x[1] - &x[0]` — needs the element size (4 for int).
2. b133's GLOBAL-INIT address `const u16 *wp = &wide[204]` — relies on the old
   fall-through value; giving it the real element stride breaks wp's computed
   value.
So the real fix must DISENTANGLE these: the ptrdiff lowering should compute the
element stride from the addressed base directly (not via IRPointerStride(AN_ADDR)),
leaving the global-init-address path's IRPointerStride(AN_ADDR) untouched — OR
the global-init path must stop routing through IRPointerStride. Find where the
`&wide[204]` global initializer calls IRPointerStride and split the two. Track A
(shared ir.inc), focused session. b133 is in test-core, so the gate guards it.
