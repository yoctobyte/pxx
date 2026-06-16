# Cross compiler.pas probe walls

- **Type:** feature
- **Status:** done
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

Baseline results after commit `3047bdd`:

```text
i386    line 86    target i386: only ordinal/pointer/string variables supported yet
aarch64 line 86    target aarch64: non-integer binop not yet supported
arm32   line 35914 target arm32: builtin/special call not yet supported
```

Current results:

```text
i386    ok         emits /tmp/compiler_i386
aarch64 ok         emits /tmp/compiler_aarch64
arm32   ok         emits /tmp/compiler_arm32
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

- **i386 line 123:** Int64/large-constant support in the `FloatToStr` builtin
  body. The previous fixed-string admission, fixed-string result, and internal
  `Double` parameter walls have been cleared.
- **AArch64 line 86:** non-integer binop support on an early compiler expression;
  likely a legacy-string / pointer-sized expression lowering gap.
- **ARM32:** stage-1 emit is clear. The former line 35914 wall was
  `ArgCount` / `ParamStr` argv handling.

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
- 2026-06-13 — advanced the i386 probe from line 86 to line 123 by admitting
  legacy fixed strings in the i386 scalar/result gates and adding internal
  `Single`/`Double` parameter stack handling. Added `test_i386_float_params`
  and kept `make test-i386` green.
- 2026-06-13 — cleared the ARM32 line 35914 wall. ARM32 now saves the initial
  stack pointer, lowers `ArgCount`, managed `ParamStr`, and fixed-string
  `ArgStr`, and emits `compiler/compiler.pas` with `--target=arm32`. Added
  `test_arm32_arg_runtime` and kept `make test-arm32` green.
- 2026-06-13 — cleared the i386 and AArch64 stage-1 emit walls. The burn-down
  covered fixed-string concat/results on AArch64, managed-string `SetLength`,
  constant `in` lowering, managed aggregate local zero-init, `LoadFile`, the
  `SysOpen`/`SysWrite`/`SysClose`/`SysFchmod` family, and argv runtime
  (`ArgCount`, managed `ParamStr`, fixed `ArgStr`) on the remaining Linux cross
  targets. `compiler/compiler.pas` now emits for i386, AArch64, and ARM32 with
  `-dPXX_MANAGED_STRING`. Added i386/AArch64 oracle coverage for setlen-str,
  in-operator, loadfile, sysopen-family, and args; `make test-i386
  test-aarch64 test-arm32` is green.

## Closure (2026-06-16)

`feature-cross-bootstrap-selfhost` is DONE — byte-identical self-fixedpoint on
i386/aarch64/arm32 (and x86-64). This ticket existed to unblock that gate, so its
blocking purpose is met: every code path `compiler.pas` itself exercises now
works byte-identically on all cross targets. Residual gaps are only in language
features the compiler does NOT self-use (e.g. classes, interfaces, some param/
ABI shapes user code hits) — those move to the language-surface hardening effort
driven by the synthetic conformance harness
([[feature-synthetic-feature-matrix-test]]). Closed.
