# Cross compiler.pas probe walls

- **Type:** feature
- **Status:** working
- **Owner:** codex
- **Unblocks:** feature-cross-bootstrap-selfhost
- **Opened:** 2026-06-13 (after arm32 SysOpen family milestone)

## Motivation

The full cross self-host fixedpoint gate is still too large to attack as one
step. Before a target can self-host under QEMU, the native compiler must at
least be able to compile `compiler/compiler.pas` for that target.

This ticket tracks the current stage-1 probe walls precisely and keeps them from
getting buried across several broader backend tickets.

## Current Probe

Run from repo root:

```sh
for arch in i386 aarch64 arm32; do
  ./compiler/pascal26 -dPXX_MANAGED_STRING --target=$arch \
    compiler/compiler.pas /tmp/compiler_$arch
done
```

Current results after commit `3047bdd`:

```text
i386    line 86    target i386: only ordinal/pointer/string variables supported yet
aarch64 line 86    target aarch64: non-integer binop not yet supported
arm32   line 35914 target arm32: builtin/special call not yet supported
```

Line numbers are from the expanded compiler source stream reported by
`pascal26`, not necessarily direct line numbers in `compiler/compiler.pas`.

## Scope

- Add or keep a repeatable probe recipe that reports the current wall for each
  Linux cross target.
- Burn down the three current stage-1 walls enough that `compiler.pas` emits a
  target binary for i386, AArch64, and ARM32.
- Keep focused oracle tests for each backend behavior fixed on the way.
- Avoid folding in the full QEMU self-host fixedpoint. That remains
  `feature-cross-bootstrap-selfhost` once stage-1 emits exist.

## Likely Ownership Split

- **i386 line 86:** aggregate/local variable support; related to
  `feature-cross-managed-aggregate-locals` and `feature-cross-codegen-gaps`.
- **AArch64 line 86:** non-integer binop support on an early compiler expression;
  likely a legacy-string / pointer-sized expression lowering gap.
- **ARM32 line 35914:** remaining unhandled special call; likely around
  `ArgCount` / `ArgStr` or another compiler main-program special.

## Acceptance

- `compiler/compiler.pas` compiles successfully with
  `-dPXX_MANAGED_STRING --target=i386`.
- `compiler/compiler.pas` compiles successfully with
  `-dPXX_MANAGED_STRING --target=aarch64`.
- `compiler/compiler.pas` compiles successfully with
  `-dPXX_MANAGED_STRING --target=arm32`.
- Existing `make test`, cross target suites, and progress check remain green.

## Log

- 2026-06-13 — ticket opened and claimed by Codex after the SysOpen-family
  milestone. Baseline probe results recorded above.
