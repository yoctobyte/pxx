---
prio: 18
track: C
summary: 'BOTH ESP-IDF legs are WIRED: tools/run_c_conformance_esp.sh --chip esp32c3|esp32s3 (Makefile targets test-c-conformance-esp32c3 / -esp32s3) runs the c-testsuite through a relinked IDF image per test under QEMU and reads each return value off the serial console. LATEST RUN 2026-09-25, compiler 5852ed1d21c6 at tree ed6297d5b, population = the 220 files of library_candidates/c-testsuite/tests/single-exec, run sequentially (S3, then C3): esp32c3 219 pass / 0 fail / 1 skip, esp32s3 219 / 0 / 1. The one skip is 00187 on both chips (no filesystem in the image). Earlier row, KEPT: 2026-09-24 at 5b95400c1a, c3 218/1/1 and s3 217/2/1. The c3 delta is 00053, fixed by a424ae12b (C tag block scope); s3 was already 219/0/1 at e1648bcb4. Host load can crash a row with an IDF interrupt-watchdog timeout (00040 did once); re-run such a row alone before calling it a codegen bug. Bare metal is out by design: bare carries no crtl.'
---

# C conformance / feature coverage on ESP (xtensa + ESP32-C3 riscv32 bare)

- **Type:** feature (test coverage). Track C (+ A for backend gaps found).
- **Split 2026-07-08** out of [[feature-c-cross-target-feature-coverage]]: the
  desktop matrix (i386/aarch64/arm32/riscv32 QEMU) landed as
  `make test-c-conformance-cross` + `test-lua-cross`; the ESP bare/QEMU leg
  needs its own harness plumbing and stays open here.

## Scope
- Pick the c-testsuite subset that makes sense bare-metal (no
  files/argv/stdout contract → needs the esp harness's UART capture, see
  `tools/esp_run_bare.sh`) or route through the hosted-riscv32 ESP-C3 path.
- Wire a make target analogous to `test-c-conformance-<arch>` with an
  explicit per-target skip file; file per-gap Track A tickets.

## Notes
- ESP C entry stub status unknown — desktop targets got theirs in the
  2026-06-29 arc; xtensa/ESP may still raise "C program entry stub not
  implemented for this target yet". First step is a bare
  `int main(void){return 42;}` probe on the esp harness.

## 2026-09-24 — C3 wired; three walls in front of it removed (frankS)

Owner: *"c-conformance is desired"*. Getting any C program to RUN under ESP-IDF
took three fixes first, all measured on esp32c3 under QEMU:

1. **main never ran.** The ESP object writer exports `app_main` at `.text+0`,
   where Pascal puts its body; C put nothing there, so IDF called whatever
   routine came first (a three-argument helper, in the case measured). True in
   pinned v416 as well: C through the IDF route had built and never executed.
   riscv32 ESP objects now get a C entry stub at offset 0 (a fake zeroed
   initial stack, the initializer shell, `main(0, argv)` or the source's own
   `app_main`, the finalizers, return to IDF).
2. **crtl collided with picolibc.** 41 of 323 exported globals, plus `errno`
   (TLS in IDF). crtl is now private in an ESP object (`ObjRuntimeIsPrivate`):
   local code, no exported state; it reaches IDF through the PAL, as the
   Pascal RTL does. Whether ESP C should use IDF's libc instead is an OPEN
   owner question -- his lean, 2026-09-24: *"it makes most sense to just use
   IDF's libraries ... but i'm not sure ... it's a choice - wrap it and keep
   best portability, or dont wrap it but programmer must be aware"*. This is
   the "wrap it" arm; do not start the other without his call.
3. **stdout went nowhere.** The ESP PAL refused fds 0-2; they now go through
   picolibc's putchar/getchar exactly as builtinheap's PXXIdfStdWrite does.

Two smaller ones the run found: an unreferenced `extern int x;` was refused as
a data import (00094.c; now only an import something READS is refused), and
the 1 MiB stock app partition overflowed on 00200.c (the harness's private
project copy takes IDF's 1.5 MiB single-app table).

Harness controls: a wrong-output, a nonzero-return and a null-store row each
FAIL for the right reason, and a correct row passes; a missing suite is exit 2,
not SKIP-and-0. Numbers: 216 rows at compiler sha `a23e896320ec`, the three
re-runs (00094, 00200, 00187) at `131ae6c99230`, which differs only by the
import-refusal change.

Side findings. Filed: `bug-c-a-c-call-to-an-external-variadic-function-on-esp-riscv32-reaches-it-without-its-arguments`
(esp_rom_printf from C prints nothing). Noted, not filed: `--target=esp32c3`
alone builds a HOSTED-linux object (0 undefined symbols), not an IDF one --
use `--target=riscv32 --platform=esp`, as tools/esp_run.sh does. And 00207.c
(VLA) PASSES here while `pxx.skip.riscv32` skips it as "alloca is x86-64
only" -- that skip may be stale; not re-measured on the desktop riscv32 leg.

## 2026-09-24 (frankS): the esp32s3 leg

Harness gained `--chip esp32s3` (hello-s3, `--target=xtensa
--xtensa-abi=windowed --platform=esp`, qemu-system-xtensa), a comma list for
`--only`, a 24-line diff, and C99's fall-off-main rule applied for a test whose
`main` has no `return` (the rename to pxx_conf_main takes it out of the
compiler's own rule; exactly 00206/00211/00212 in the suite, census by script).

First full s3 run, compiler 17be23f99ad8: 209 pass / 10 fail / 1 skip. The nine
non-00053 reds were five real xtensa bugs plus the harness artefact, fixed and
re-run at f8f9d3f827d3 (see done/feature-a-variadic-c-functions-on-the-windowed-xtensa-abi).
216/3/1 is therefore 211 rows at 17be23f99ad8 and 9 at later binaries whose
diffs are the fixes named there; a clean single-binary full run has NOT been
done. esp32c3 re-checked on a 5-test subset at f8f9d3f827d3, all pass.

## 2026-09-24 (frankS): the clean run

One binary, one tree: 5b95400c1a == origin, compiler sha256
41013170dc747df106e246fc429e6262509f8518fc72de3ea88069761b3ac29e. Sharded
3 + 3 concurrently while two other seats were building (load avg ~11-12 on 12
threads).

| chip | concurrent | solo re-run of the fails |
|---|---|---|
| esp32c3 | 217 / 2 / 1 -- 00053 (compile), 00040 (Interrupt wdt crash) | 00040 PASS 3/3 |
| esp32s3 | 217 / 2 / 1 -- 00053 (compile), 00207 (alloca, compile) | deterministic compile errors, not re-run |

So c3 = 218/1/1 and s3 = 217/2/1, with 00040's concurrent crash recorded as a
LOAD ARTEFACT (it had already tripped at 10 QEMUs in an aborted earlier run).
The harness header now says so. An earlier attempt at 563f6937f9 was abandoned
midway because a push pulled compiler/builtin/builtinheap.pas, a per-program
compile input, into the tree under the s3 half; the compiler binary sha did not
change, which is why the binary sha alone would not have caught it.
