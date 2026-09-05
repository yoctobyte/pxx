#!/usr/bin/env sh
# SPDX-License-Identifier: MPL-2.0
# Run a PXX-emitted binary for a given CPU target, under QEMU user-mode
# emulation when the host cannot execute it natively.
#
#   tools/run_target.sh <arch> <binary> [args...]
#
# arch: x86_64 | i386 | aarch64 | arm32 | riscv32 | riscv64 | xtensa | wasm32
#
# Exit code is the program's exit code (QEMU passes it through), so the
# existing `test "$(...)" = ...` Makefile assertions work unchanged.
# PXX binaries are static and syscall-only, so no -L sysroot is needed;
# if a dynamically linked test ever crosses an arch boundary it must add
# QEMU_LD_PREFIX for the target's interpreter.
set -eu

if [ $# -lt 2 ]; then
  echo "usage: $0 <arch> <binary> [args...]" >&2
  exit 2
fi

arch="$1"; shift
bin="$1"; shift

# Dynamically linked PXX binaries (external C calls) need the guest ld.so + libc.
# If a sysroot was provisioned (tools/install_cross_sysroot.sh) and the caller
# did not already set QEMU_LD_PREFIX, point QEMU at it. Harmless for the common
# static/syscall-only binaries.
xroot="${PXX_CROSS_SYSROOT:-$HOME/.cache/pxx-cross}"
if [ -z "${QEMU_LD_PREFIX:-}" ] && [ -d "$xroot/$arch" ]; then
  QEMU_LD_PREFIX="$xroot/$arch"
  export QEMU_LD_PREFIX
fi

# AN ABSENT RUNNER MUST SAY SO ON *STDOUT*, and that is this helper's entire
# reason to exist. Every Makefile assertion invokes this script inside
# `"$(tools/run_target.sh ...)"`, and a command substitution captures stdout and
# THROWS THE EXIT CODE AWAY -- there is no `set -e` reachable from an argument
# position. So a runner that reported its absence only on stderr handed
# expect_same.sh the EMPTY STRING, and the row failed as a CONTENT MISMATCH
# against the expected output. The diff then reads exactly like the target
# producing nothing, i.e. like a compiler bug.
#
# MEASURED 2026-09-04, and it cost real triage: host seven HAD no wasmtime, and
# six test-core rows auto-filed as regressions in one run -- fpn26/wasm32,
# fpfld26/wasm32, tidref26/wasm32, dsspal26/wasm32, entpal26/wasm32 and the
# futex row -- each naming a different test and a different commit. Four of them
# were read as four separate defects in freshly added tests. All six were one
# missing binary. The compiler was correct on every one: re-run on a host WITH
# wasmtime, at the same commit, every row passes.
#
# PREMISE MOVED 2026-09-05: seven reports wasmtime 48.0.1 installed. The
# INCIDENT above is history and stays; the present-tense reading of it does not.
# It was being cited as a live fact this evening -- correctly, from a header that
# had gone stale -- to justify a design choice. THE DESIGN CHOICE IS UNAFFECTED
# and stands on its own: a quick-tier row that reddens on a host gap is still
# worse than none, and asserting an IMPORT rather than an exit code matches the
# assertion class to the defect class without needing any runtime at all. What
# changes is only that "seven has no wasmtime" is no longer a premise anyone may
# reason from. Cite `command -v wasmtime` on the box, never this comment.
#
# NOT A SKIP. An unrun test is not a passing test and this still exits nonzero
# and still reddens the row -- what changes is that the row now names the HOST
# instead of accusing the target. The marker goes to both streams because
# whoever reads a log sees stderr and whoever reads an assertion diff sees only
# stdout, and the 2026-09-04 tickets were written by something that saw only the
# second.
runner_absent() {
  echo "RUNNER-ABSENT: $1 not found, so target '$arch' was NOT RUN. $2"
  echo "RUNNER-ABSENT: $1 not found, so target '$arch' was NOT RUN. $2" >&2
  exit 2
}

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    runner_absent "$1" "Run tools/install_qemu.sh. This is a host gap, not a result about the compiler."
  fi
}

case "$arch" in
  x86_64)
    exec "$bin" "$@"
    ;;
  i386)
    # x86-64 kernels usually exec i386 ELF natively (ia32 emulation);
    # prefer that, fall back to qemu-i386.
    #
    # stderr is NOT redirected. It used to go to /dev/null, so every i386 run
    # silently dropped the program's own diagnostics — and callers that compare
    # combined stdout+stderr byte-for-byte (tools/run_c_conformance.sh) were
    # comparing output the program never got to produce. Capturing it to a file
    # and replaying it afterwards is not equivalent either: that reorders it
    # against buffered stdout, and the interleaving is part of what is compared.
    # The cost is one "cannot execute binary file" line from the SHELL on a host
    # that cannot exec i386 ELF, just before the qemu fallback — loud and
    # diagnosable, unlike silently losing every program's stderr.
    if "$bin" "$@"; then exit 0; else rc=$?; fi
    # ENOEXEC surfaces as 126 from sh; anything else is the program's own exit
    # code — pass it through.
    if [ "$rc" != 126 ]; then exit "$rc"; fi
    need qemu-i386
    exec qemu-i386 "$bin" "$@"
    ;;
  aarch64)
    need qemu-aarch64
    exec qemu-aarch64 "$bin" "$@"
    ;;
  arm32)
    need qemu-arm
    exec qemu-arm "$bin" "$@"
    ;;
  riscv32)
    need qemu-riscv32
    exec qemu-riscv32 "$bin" "$@"
    ;;
  riscv64)
    need qemu-riscv64
    exec qemu-riscv64 "$bin" "$@"
    ;;
  xtensa)
    # Hosted xtensa under qemu-xtensa user mode. Newest arm, and the only one
    # whose target was unrunnable until 2026-08-29: xtensa had no IR_SYSCALL
    # lowering, no exit syscall, and no HeapMmap arm, so every binary either
    # spun in EmitExit's self-loop or faulted at $FFFFFFFF on its first
    # allocation. feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle
    #
    # TWO THINGS THE CALLER MUST GET RIGHT, and neither is visible here because
    # both are COMPILE-time:
    #
    #   --platform=posix, or the ESP PAL is selected and syscalls lower to
    #   PAL_ERR_UNSUPPORTED (-38) instead of trapping to the kernel.
    #
    #   --xtensa-soft-mulhigh, or ANY numeric output SIGILLs. No qemu-xtensa
    #   core implements MUL32HIGH -- measured, all 8 cores -- and integer
    #   formatting strength-reduces div-by-10 into a 64-bit multiply. Under
    #   that flag the emulator is NOT bit-identical to hardware for multiplies,
    #   so a verdict produced here must name the flag.
    #
    # No -cpu: the default core runs everything the ESP parts need. Two cores
    # are NOT interchangeable and a sweep must pin its list -- dsp3400 has no
    # MUL32 at all, and lx106 (the ESP8266 core) has no windowed ABI option.
    need qemu-xtensa
    exec qemu-xtensa "$bin" "$@"
    ;;
  wasm32)
    # wasm32 is the only arm that is NOT qemu: the artifact is a .wasm module,
    # not an ELF, so there is no CPU to emulate and wasmtime is the runtime.
    #
    # WHY THIS ARM EXISTS AT ALL: two sessions independently concluded wasm32
    # had no runner -- one from an inference it had not checked, one from this
    # script's silence -- and both were wrong. wasmtime 48.0.1 runs a
    # PXX-emitted frozen-string module correctly. The Makefile having no
    # test-wasm32 target was evidence about the Makefile, not about wasm32.
    #
    # EXIT CODE PASSTHROUGH IS MEASURED, NOT ASSUMED, because every Makefile
    # assertion here reads it and a runner that swallowed it would make each of
    # them unable to fail: `Halt(7)` returns 7 and `Halt(0)` returns 0 through
    # wasmtime, matching the QEMU arms' contract above.
    #
    # wasmtime is commonly installed under ~/.local/bin, which is on an
    # interactive PATH but not on the default one a non-login shell inherits,
    # so resolve it explicitly rather than failing with "not found" on a box
    # that has it.
    if command -v wasmtime >/dev/null 2>&1; then
      exec wasmtime "$bin" "$@"
    elif [ -x "$HOME/.local/bin/wasmtime" ]; then
      exec "$HOME/.local/bin/wasmtime" "$bin" "$@"
    else
      runner_absent "wasmtime" "Looked on PATH and in ~/.local/bin. This is a host gap, not a result about wasm32."
    fi
    ;;
  *)
    # Same stdout rule as runner_absent, for the same reason: a caller that
    # misspells an arch inside `$(...)` otherwise sees an empty string and
    # reads it as the program printing nothing.
    echo "RUNNER-ABSENT: unknown arch '$arch', so nothing was run."
    echo "unknown arch: $arch" >&2
    exit 2
    ;;
esac
