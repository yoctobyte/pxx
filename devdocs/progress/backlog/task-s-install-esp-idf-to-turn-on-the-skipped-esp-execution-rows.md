---
slug: task-s-install-esp-idf-to-turn-on-the-skipped-esp-execution-rows
track: S
prio: 40
type: task
blocked-by: []
status: backlog
summary: "ESP-IDF is not installed on plexus, so every ESP EXECUTION row in `test-esp-bare` prints 'not installed; skipped' and passes. IDF ships the Espressif qemu fork the rows already look for; the wiring is done and waiting. A download, not a code change — but it is a NETWORK + INSTALL action and needs the user's go-ahead."
---

# Install ESP-IDF so the skipped ESP execution rows actually run

## What is skipped right now, and silently

`test-esp-bare` runs each bare image against the x86-64 oracle — but every one
of those rows is guarded:

```make
@XT=$$(ls $$HOME/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa 2>/dev/null | head -1); \
if [ -z "$$XT" ]; then echo "Espressif qemu-system-xtensa not installed; esp32s3 ... skipped"; else ...
```

Measured on plexus, 2026-08-27: no `IDF_PATH`, no `~/.espressif`, no `~/esp`,
and **no `qemu-system-*` of any kind anywhere on the filesystem** — only the
stock user-mode `qemu-<arch>` binaries. So every ESP execution row is taking the
skip branch and the target passes. The *build* rows are real; the *run* rows are
not running.

That is a `bug-t-a-skip-that-cannot-say-why-is-a-pass-in-the-verdict` shape: the
suite is greener than the coverage.

## Why now

The box changed. plexus replaced borg's frank2/frank3 after the 2026-08-20 PSU
death, and **whether the old box had IDF is unrecorded** — not in the tree, not
in the box-level notes. Several open tickets say "cannot be verified on this
box" about a machine that no longer exists, so the claim needs re-establishing
either way.

## What it buys, and what it does not

**Buys:** every `test-esp-bare` execution row (bare boot, atomics, call0 large
frame, inline asm, and the new bare-float row from
[[bug-a-esp32c3-bare-profile-cannot-find-the-softfloat-repack-helper]]) starts
actually running on both chips. Today those are the only xtensa **execution**
coverage that exists, and none of it executes.

**Does not buy:** the gates on
[[bug-a-the-div-by-zero-check-is-still-missing-on-xtensa]] and
[[bug-a-xtensa-cannot-lower-an-int64-to-float-conversion]]. Those name
`test_div_by_zero_raises_on_every_target.pas`, which cannot be BUILT for an
ESP-class target at all (`UpCase: builtin helper unavailable ... not on ESP`) —
riscv32-bare fails on it too, and riscv32 passes that gate only on its **hosted**
profile. Reaching those needs
[[feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle]], which is a
different and much larger job. The two are complementary, not alternatives.

## Not done unilaterally

This is a multi-gigabyte download and a toolchain install — outward-facing and
not reversible by an `Undo`. It needs the user's explicit go-ahead, which is why
this is a ticket and not a fix.

## Gate

`make test-esp-bare` printing `esp32c3 ...ok` / `esp32s3 ...ok` on every row
instead of `...skipped`, with the UART output matching the x86-64 oracle. Then
consider whether a skipped ESP row should FAIL the target rather than pass it,
once passing is actually achievable.
