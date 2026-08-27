---
slug: task-s-install-esp-idf-to-turn-on-the-skipped-esp-execution-rows
track: S
prio: 40
type: task
blocked-by: []
status: done
summary: "ESP-IDF is not installed on plexus, so every ESP EXECUTION row in `test-esp-bare` prints 'not installed; skipped' and passes. IDF ships the Espressif qemu fork the rows already look for; the wiring is done and waiting. A download, not a code change — but it is a NETWORK + INSTALL action and needs the user's go-ahead."
owner: agent-A
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
death. **borg HAD ESP-IDF installed** (user, 2026-08-27); plexus does not, and
nothing in the tree or the box-level notes recorded either fact — which is why
several open tickets say "cannot be verified on this box" about a machine that
no longer exists, and why this is a restore rather than a first-time setup.

That also means the ESP execution coverage silently *regressed* with the
hardware move: the rows did not start skipping because anything changed in the
repo, and nothing went red to say so.

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
[[feature-a-complete-the-builtin-unit-on-the-esp-class-targets]] — which, once
done, makes those gates buildable for a bare ESP target, at which point THIS
ticket is what makes them runnable. That pairing is the cheap route;
[[feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle]] is the expensive one
and is no longer the unblock.

## Not done unilaterally

This is a multi-gigabyte download and a toolchain install — outward-facing and
not reversible by an `Undo`. It needs the user's explicit go-ahead, which is why
this is a ticket and not a fix.

## Gate

`make test-esp-bare` printing `esp32c3 ...ok` / `esp32s3 ...ok` on every row
instead of `...skipped`, with the UART output matching the x86-64 oracle. Then
consider whether a skipped ESP row should FAIL the target rather than pass it,
once passing is actually achievable.

---

## Done — 2026-08-27, plexus

Installed on the user's explicit go-ahead ("well, install IDF"):

- **ESP-IDF v6.0.1** at `~/esp/esp-idf`
- **both Espressif qemu forks**, 9.2.2 / `esp_develop_9.2.2_20250817`, at
  `~/.espressif/tools/qemu-{xtensa,riscv32}/*/qemu/bin/` — exactly the paths the
  Makefile rows probe, so no Makefile change was needed. The wiring really was
  done and waiting.

### The gate, measured

Every bare execution row now runs instead of skipping, on **both** chips, with
UART output diffed against the x86-64 oracle:

```
bare boot          esp32c3 UART == x86-64 oracle    esp32s3 UART == x86-64 oracle
bare float         esp32c3 == oracle                esp32s3 == oracle
softfloat probe    esp32c3 ok                       esp32s3 ok
```

The bare-float row is the one that mattered most: it is the first time the
`__pxx_*` soft-float kernels from
[[bug-a-esp32c3-bare-profile-cannot-find-the-softfloat-repack-helper]] have been
*executed* on either ESP ISA rather than inspected. `7 16 32 75 ESP BARE FLOAT
OK` on both chips, identical to the host.

### The installer needed three fixes to get here

It had never been run end-to-end on a current Ubuntu. All three are committed:

1. `libglib2.0-0` has no candidate under Ubuntu's `t64` renames — `set -eu`
   killed the install outright (`d273b67dd`).
2. `validate_install` sourced `export.sh` from a `#!/usr/bin/env sh` script.
   IDF's `export.sh` is bash/zsh-only and under dash prints "Could not
   automatically detect IDF_PATH" and exports nothing — so the script reported
   the whole install FAILED after it had succeeded completely. Exporting
   `IDF_PATH` first does not help; it re-derives it.
3. Not idempotent after its own first run: it clones the default branch then
   checks out the tag, leaving untracked submodule dirs that exist on master and
   not on v6.0.1, and the dirty check then refused for files nobody wrote.

Fix 2 is the one worth remembering — a **successful** install that reports
failure is the shape that wastes the most time.

### Follow-on, deliberately not done here

The ticket asked whether a skipped ESP row should FAIL rather than pass. It
should not be decided unilaterally: making the skip fatal turns any box without
a multi-gigabyte toolchain red, which is most of them, and the honest fix is a
verdict that can distinguish "skipped" from "passed" rather than a louder skip.
That is `bug-t-a-skip-that-cannot-say-why-is-a-pass-in-the-verdict`'s territory
and belongs to Track T, so it is left there rather than duplicated.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.
