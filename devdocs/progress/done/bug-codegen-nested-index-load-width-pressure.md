# Codegen miscompiles nested integer-array index load width under register pressure

- **Type:** bug
- **Status:** done (fixed indirectly)
- **Owner:** —
- **Opened:** 2026-06-16 (found while landing static-array→open-array Length, ac6d98f)
- **Closed:** 2026-06-16

## Resolution — fixed indirectly by this cycle's sign-extension work

The landmine was a lost 32→64 sign-extension on a nested index load inside the
oversized `IRLowerCallArg`. This cycle's pointer-arith / parenthesised-deref fixes
(notably `d3e12d0` — the grouped-expression deref + element-scaled pointer
arithmetic that had been miscompiling negative/unextended index values) addressed
the same sign-extension class. Re-inlined the `TryStaticToOpenArray` guard back
into `IRLowerCallArg` (the exact indexing-heavy shape that used to crash the
self-host) and `make bootstrap` + all four suites + `make cross-bootstrap` are
**byte-identical, no crash**. The helper workaround is removed; the guard lives
inline again.

## Symptom

In a sufficiently large/high-pressure function, a **nested integer-array index**
`arr2[arr1[i]]` (or `Syms[ASTIVal[arg]].field`) can be miscompiled: the inner
`arr1[i]` element — a 4-byte `Integer` that must be loaded sign-extended into a
64-bit register (`movsxd`) — is instead emitted as a plain 8-byte load (`mov
(%rax),%rax`). A `-1` element then reads as `0xffffffff`, used as an index →
wild out-of-bounds dereference → SIGSEGV.

Concretely: adding the open-array guard (which contains `Syms[ASTIVal[argAST]].…`)
inline into the already-huge `IRLowerCallArg` made the **self-hosted** compiler
miscompile *itself* (BUILD crashed in stage-3 self-compile). The exact same
source pattern compiles correctly everywhere else; only that one oversized
function tipped over a pressure threshold.

## Not yet root-caused

- It is **not** a stack overflow / runtime issue — it is a deterministic
  compile-time wrong-instruction-selection in the x86-64 backend (and possibly
  the others; only x86-64 confirmed, via the self-host crash).
- The mechanism is pinned (wrong load width: `mov` instead of `movsxd`); the
  exact codegen branch that flips the inner load's width/type under pressure is
  NOT pinned.
- Current mitigation (commit ac6d98f) is a **workaround**: the guard+copy were
  moved into a small helper `TryStaticToOpenArray`, so `IRLowerCallArg` stays
  under the threshold. The underlying bug remains and could miscompile any other
  large function with a nested integer-array index.

## Repro path

1. Inline an indexing-heavy expression (e.g. `Syms[ASTIVal[x]].f`) into a large
   hot function such as `IRLowerCallArg`.
2. `make bootstrap`; stage-3 (BUILD compiling compiler.pas) SIGSEGVs.
3. gdb BUILD: crash is `movzbq (%rax)` with `%rax` a wild value; trace shows an
   inner `mov (%rax),%rax` where a `movsxd` was required.

Bisection proof: minimal int-only code in `IRLowerCallArg` = OK; any indexing
expression in its body = miscompile; same code in a helper = OK.

## Why it matters

Latent landmine for the "top-notch compiler" goal: silently miscompiles correct
source past a size threshold. Likely related to register allocation / spill or
to the inner-index value's IR type losing `tyInteger` (4-byte signed) under
pressure. Fixing it removes a whole class of size-sensitive miscompiles.

## 2026-06-16 — probe session (still open)

Hunted for a standalone repro with synthetic large functions doing nested
array-of-record indexing (`tab[idxs[j]].c`) under local-count pressure. The
load-width miscompile itself did **not** reproduce: once the unrelated bugs below
were out of the way, the array-of-record nested index produced correct output on
a clean (FPC-built) compiler regardless of function size, and self-host stayed
byte-identical. So the specific `mov`-instead-of-`movsxd` inner-load flip is still
unpinned — it may need the exact compiler.pas shape, or my codegen changes this
cycle (short-circuit and/or) shifted whatever threshold it sat on.

Two **distinct** real bugs were found and fixed while probing (do not conflate
with this one):
- **>64 names in one `var` line overflowed `names: array[0..63]`** in
  ParseVarSection / ParseLazyVarDeclAST, silently corrupting the compiler (flipped
  isAsmFunc → "expected asm", or SIGSEGV depending on the build). Fixed: bounded
  to MAX_DECL_NAMES (256) + a guard error. (My first synthetic put all locals on
  one line, hitting this instead.)
- **`(p)^` / `(p + k)^` deref of a parenthesised expression** was miscompiled —
  the grouping-paren case ran no postfix `^`/`.`/`[` loop, so the `^` dangled and
  the pointer (not the pointee) was used; negative offsets in pointer arithmetic
  then read wild addresses. Fixed in ParseFactor (test_cross_ptr_arith).

Both were sign/width/pointer-adjacent, which is why the probe kept surfacing them,
but neither is the size-threshold inner-load-width flip this ticket describes.

Next idea if resumed: revert the `TryStaticToOpenArray` helper (re-inline the
guard into IRLowerCallArg) on the current tree and gdb the FPC-built BUILD stage
directly — the FPC build crashes too, so it does not need self-host, and it has
symbols.

Update (later same day): **re-inlined the guard and it no longer reproduces.** A
flag-based inline (boolean `caHandled` + `not (...)` guards, the body's nested
`Syms[...]`/`ASTIVal[...]` reads kept shallow, no indexing-heavy early-`Exit`
expression) self-hosts byte-identical (two-gen fixedpoint OK, code=2002931B). So
the trigger is sensitive to the *exact* expression shape in the hot function, not
merely its size — consistent with a wrong-load-width-under-expression-pressure
mechanism. The original ac6d98f inline (indexing expressions placed directly in
the arg-lowering path) is what tipped it; this cycle's codegen changes
(short-circuit, paren-deref) may also have moved the threshold. The
`TryStaticToOpenArray` helper workaround is kept (committed); the underlying
load-width selection bug remains latent and unpinned. To pin it, reconstruct the
*original* indexing-heavy inline shape (not a flag-based rewrite) and gdb the
FPC-`-g` BUILD stage.

## Acceptance

- A minimal standalone repro (no self-host needed) that miscompiles on a clean
  compiler — i.e. find a single function shape that triggers the wrong load
  width without bootstrap. (Self-host is the only known trigger so far.)
- Root-cause the codegen path; fix so the inner index always loads at its real
  element width with correct sign-extension regardless of function size.
- Re-inline the open-array guard into `IRLowerCallArg` (revert the helper
  workaround) and confirm bootstrap stays byte-identical.
