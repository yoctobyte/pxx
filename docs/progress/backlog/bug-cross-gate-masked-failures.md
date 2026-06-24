# bug: cross gates red on two pre-existing tests (were masked behind ArgStr)

- **Type:** bug (Track A — cross codegen)
- **Status:** backlog
- **Found:** 2026-06-24, after fixing `bug-argstr-managed-dest-cross`
- **Severity:** medium — keeps `make test-i386` / `test-aarch64` / `test-arm32`
  red. Both are independent of the ArgStr fix; they were simply hidden because
  the gate stops at the first failing test and `test_arm32_arg_runtime` (earlier
  in the gate) failed first.

## Background

The cross gate has been red at `test_arm32_arg_runtime` since that test landed
(7b20bef, 2026-06-23). With ArgStr now fixed (`bug-argstr-managed-dest-cross`,
2026-06-24) the gate runs further and exposes two failures that were accumulating
unnoticed behind the early stop. Both reproduce on HEAD with the ArgStr change
stashed, so neither is a regression from that work.

## Failure 1 — `test_cross_frozen_strlen_deref` (i386 + arm32)

Run under `-dPXX_MANAGED_STRING`. Cross output diverges from the x86-64 oracle on
the 2nd/3rd lines:

```
i386 / arm32 : 5 / 1869566548 / 1869566548 / 26984 / 26984
x86-64 oracle: 5 / 500085772884 / 500085772884 / 26984 / 26984
```

A done ticket exists — `bug-frozen-string-length-pointer-deref-cross` (resolved
2026-06-19, `Length(p^)` of a frozen string returning 0 on cross). The current
divergence is a *different* number (not 0), so either that fix regressed for this
test shape or the test was added/extended afterward in a state that never passed
cross. Note x86-64 itself prints `500085772884` (a 64-bit read of string bytes),
so the test asserts cross==x86-64 on what is already an odd value — re-examine
whether the test or the codegen is wrong. aarch64 was not reached (it dies earlier
on Failure 2).

## Failure 2 — `test_classref` (aarch64)

```
./compiler/pascal26 --target=aarch64 test/test_classref.pas /tmp/x
pascal26:186: error: target aarch64: load through pointer of this type not yet supported ()
```

A class-reference / metaclass construct at `test_classref.pas:186` lowers to a
load the aarch64 backend rejects ("load through pointer of this type not yet
supported"). `feature-metaclass-construct-dispatch` is marked done as
"target-independent IR, all backends", but this particular classref load is not
handled on aarch64. i386/arm32 were not checked for the same test (gate ordering).

## Acceptance

- `make test-i386`, `make test-aarch64`, `make test-arm32` fully green.
- Each fix verified against the x86-64 oracle under `tools/run_target.sh`.

## Repro

```
git stash    # (if the ArgStr change is uncommitted; not needed once committed)
./compiler/pascal26 -dPXX_MANAGED_STRING --target=i386 test/test_cross_frozen_strlen_deref.pas /tmp/fs
tools/run_target.sh i386 /tmp/fs                 # vs the x86-64 build's output
./compiler/pascal26 --target=aarch64 test/test_classref.pas /tmp/cr   # errors at :186
```
