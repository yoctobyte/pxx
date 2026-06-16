# Codegen miscompiles nested integer-array index load width under register pressure

- **Type:** bug
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-16 (found while landing static-array→open-array Length, ac6d98f)

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

## Acceptance

- A minimal standalone repro (no self-host needed) that miscompiles on a clean
  compiler — i.e. find a single function shape that triggers the wrong load
  width without bootstrap. (Self-host is the only known trigger so far.)
- Root-cause the codegen path; fix so the inner index always loads at its real
  element width with correct sign-extension regardless of function size.
- Re-inline the open-array guard into `IRLowerCallArg` (revert the helper
  workaround) and confirm bootstrap stays byte-identical.
