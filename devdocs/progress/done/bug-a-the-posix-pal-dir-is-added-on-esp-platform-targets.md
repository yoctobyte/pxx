---
track: A+S
prio: 45
type: bug
blocked-by: []
summary: "AddDefaultPasUnitDirs (compiler.pas) guards the posix PAL search dir on TargetIsEspClass — bare-ness — when the question is which PAL the platform wants. So an ESP-PLATFORM target that is not bare (xtensa under IDF, riscv32 under --platform=esp) gets lib/rtl/platform/posix/ on its unit path, and the esp PAL dir is never added by the compiler at all: every ESP build passes -Fulib/rtl/platform/esp by hand. Latent as of regression-test-emit-obj-cxtensa-obj — nothing on that path pulls the PAL any more — but the guard is still wrong and the next thing to pull platform_backend on an ESP target resolves the posix one."
status: done
owner: frankS
---

# The posix PAL dir is added on ESP-platform targets

- **Type:** bug (toolchain / unit search path) — **Track A**, **S** tag (the
  platform in question is ESP).
- **Filed:** 2026-08-29 by frankA, while resolving
  [[regression-test-emit-obj-cxtensa-obj]]. **Split out deliberately rather
  than fixed there**: that ticket's fix removes the only path that reached
  this, so fixing both together would have hidden which change did what.

## The defect

`AddDefaultPasUnitDirs` (`compiler/compiler.pas:196`) appends the **posix** PAL
root and exits early on:

```pascal
if NoDefaultRtl or TargetIsEspClass then Exit;
```

`TargetIsEspClass` means *bare metal, no RTL* since `cbfdb5de8`. The question
this function is asking is *which PAL does this platform want*, and the axis
that answers it is `TargetPlatform`. They diverge exactly on the non-bare ESP
profile:

| target / flags | `TargetIsEspClass` | `TargetPlatform` | PAL dir added |
| --- | --- | --- | --- |
| `--target=xtensa` | False | **ESP** | **posix** — wrong |
| `--target=xtensa --platform=esp` | False | **ESP** | **posix** — wrong |
| `--target=riscv32 --platform=esp` | False | **ESP** | **posix** — wrong |
| `--target=xtensa --esp-profile=bare` | True | ESP | none (correct) |
| `--target=riscv32` (hosted) | False | POSIX | posix (correct) |

Measured on the pinned v389 binary: `--platform=esp` does **not** change which
PAL dir is added, which is the whole tell — an explicit platform flag that the
platform-dir chooser does not consult.

## The other half: nothing ever adds the esp PAL

`grep` for who puts `lib/rtl/platform/esp/` on a search path returns **no
compiler code at all** — only callers passing `-Fu` by hand:

```
Makefile:14594   $(PXX_STABLE) --platform=esp -Fulib/rtl/platform/esp ...
examples/esp32/timer-s3/build.sh:19   -Fu"$REPO_ROOT/lib/rtl/platform/esp"
examples/esp32/timer-c3/build.sh:16   -Fu"$REPO_ROOT/lib/rtl/platform/esp"
tools/library_suite.sh:115            -Fu"$ROOT/lib/rtl/platform/esp"
```

`lib/rtl/platform/esp/platform_backend.pas` exists and is real. Every ESP build
in the tree compensates for the compiler not knowing about it, and because `-Fu`
is searched *before* the defaults, the hand-passed dir wins and the wrong
default is invisible. That is why this survived: it is masked at every call site
that matters.

## Why it is only p45

`regression-test-emit-obj-cxtensa-obj` removed the reachable consequence — the C
driver no longer pulls the hosted RTL on an ESP platform, so nothing on that
path asks for `platform_backend` any more. What remains is a wrong default that
is currently unreachable *and papered over by four call sites*. Prio reflects
reachability, not correctness: it is a trap armed for the next person, not a
live failure.

**Do not "fix" it by deleting the early exit.** The posix dir would still be
wrong; the fix is to select the PAL from `TargetPlatform` and add the **esp**
root when the platform is ESP.

## Why it is S's call and not a drive-by

Adding the esp PAL as a default changes what `platform_backend` resolves to for
`riscv32 --platform=esp` — today it silently gets the **posix** backend, whose
raw Linux syscalls under FreeRTOS/IDF are the failure mode
`bug-esp-idf-heap-linux-mmap-ecall` already recorded once. Making it resolve the
esp backend is very probably correct and is also a behaviour change on a
shipping profile, so it wants the ESP campaign's eyes and a real-hardware
check, not a one-line edit from a passing lane.

## Repro

```
./stable_linux_amd64/default/pinned --where --target=xtensa --platform=esp
```

`--where` prints the search path this function builds. Expect
`lib/rtl/platform/posix/` on an ESP platform, and no esp root anywhere.

## Gate

Track A's: `make compiler/pascal26` plus `--where` showing the esp root on ESP
platforms and posix elsewhere. Cross matters — let Track T sweep. If the esp
backend becomes a default, the esp32 example builds and
`test/lib_platform_esp.pas` are the real check, and their now-redundant `-Fu`
lines should stay (an explicit override that agrees with the default is not a
bug).

## Repro correction 2026-08-29 (frankS) — the command as written cannot show the bug

The `## Repro` line above is:

```
./stable_linux_amd64/default/pinned --where --target=xtensa --platform=esp
```

**`--where` before the target flags silently ignores them.** Run exactly as
written it prints `lib/rtl/platform/posix/` for *every* target — including
`--esp-profile=bare`, which this ticket correctly says should add none. So
following the repro literally shows a uniform result, hides the very axis the
ticket is about, and makes the bare row look broken too.

Put `--where` **last**:

```
./compiler/pascal26 --target=xtensa --platform=esp --where
```

Re-measured that way on `cf72dd641`, and the ticket's table is **confirmed
exactly as written** — the diagnosis was right, only the repro line was wrong:

| invocation | PAL dir added |
| --- | --- |
| `--target=xtensa --where` | posix — wrong |
| `--target=xtensa --platform=esp --where` | posix — wrong |
| `--target=riscv32 --platform=esp --where` | posix — wrong |
| `--target=xtensa --esp-profile=bare --where` | **none** (correct) |
| `--target=riscv32 --where` | posix (correct) |
| `--target=x86_64 --where` | posix (correct) |

So `--platform=esp` genuinely does not change which PAL dir is added, and no
esp root is added on any invocation — both halves of the defect stand.

Not claimed: the fix edits `AddDefaultPasUnitDirs` in `compiler/compiler.pas`,
which is Track A's shared ground and outside the file grant frankS is holding
(`ir_codegen_xtensa.inc`, `lib/rtl/platform/esp/**`, `examples/esp32/**`).
Left for A, or for S once the grant is widened.

## Resolution (frankS, 2026-08-29)

Fixed in `compiler/compiler.pas`. **Two defects, not one** — the second was not
in the ticket and is what actually kept the first invisible.

### Defect 1 — the PAL was selected on the wrong axis (as filed)

`AddDefaultPasUnitDirs` hardcoded `posix` in **four** spellings (the `PXX_HOME`
branch, two ExeDir-anchored guesses, and the CWD fallback). Now the PAL is
chosen once into a `pal` local from `TargetPlatform` and substituted into all
four. Selected once rather than branched four times on purpose: the four are
one decision, and four copies are what drift
(`devdocs/dev/normalise-dont-special-case.md`).

The `if NoDefaultRtl or TargetIsEspClass then Exit;` early exit **stays** —
bare ESP has no RTL at all and correctly gets no PAL — so the new selector only
ever chooses between a hosted-POSIX and an ESP-platform build. Per the ticket's
instruction, the early exit was not deleted.

### Defect 2 — `--where` answered before the platform was derived

The ticket's gate asks for "`--where` showing the esp root on ESP platforms".
Fixing defect 1 alone did **not** achieve that for `--target=xtensa`, and the
reason is a second bug: `--where` is handled *inside* the argument loop
(`compiler.pas:957`, `PrintWhere; Halt(0)`), while the platform derivation ran
after the loop finished. So `--where` reported the PAL of the pre-derivation
default (`PLATFORM_POSIX`, set at init) rather than the one a real compile
would use.

That directly defeats the promise in `AddDefaultPasUnitDirs`'s own header
comment — the function was extracted *specifically* so "`pxx --where` reports
the same list a real compile builds", because "a diagnostic that re-derives the
search path is a diagnostic that goes stale silently". The extraction was
right; the call ordering silently undid it.

Fixed the same way, not by duplicating the rule: the derivation is now
`DeriveTargetPlatform`, called from both `PrintWhere` and the main body. One
copy, two callers.

### The ticket's "latent, currently unreachable" framing was too generous

`## Why it is only p45` says the reachable consequence was removed and what
remains is "a wrong default that is currently unreachable and papered over by
four call sites". Measured against the **pinned v392** binary, that holds only
for in-tree builds. For anyone not passing `-Fu` by hand it was a hard
compile failure, not a latent trap:

```
$ stable_linux_amd64/default/pinned --target=xtensa pal.pas pal.o
  in: stable_linux_amd64/default/../../lib/rtl/platform/posix/platform_backend.pas
  near:  Integer  __pxxrawsyscall  SYS_getgid >>>
pascal26: too many errors, stopping
```

The posix PAL does not compile on xtensa at all — its raw Linux syscalls have
no `SYS_getgid` there. The error even names the wrong PAL in its own `in:`
line. So `uses platform` on a plain `--target=xtensa` was broken outright; the
four hand-passed `-Fu` call sites hid it from every build in the tree, which is
exactly why it read as unreachable. Not re-ranked, since it is now closed.

### The behaviour change the ticket wanted ESP eyes on — measured

`--target=riscv32 --platform=esp` previously compiled *fine* while silently
binding the **posix** backend, which is the FreeRTOS/IDF failure
`bug-esp-idf-heap-linux-mmap-ecall` already recorded once. It now binds the esp
backend:

| | pinned v392 | fixed |
| --- | --- | --- |
| `riscv32 --platform=esp`, `uses platform` | ok, **posix** backend, `code=410740B` | ok, **esp** backend, `code=376556B` |

This is the intended change and the one the ticket flagged as wanting the
campaign's judgement. It is right: an ESP-platform build binding a PAL of raw
Linux syscalls is the silent-wrong-value case, and it is now impossible by
default.

### Verified (binary `3e5b376ad8f5`, self-host fixedpoint, converged 1 round)

`--where` and the real compile now agree on every row, which is the property
defect 2 broke:

| invocation | `--where` | real compile |
| --- | --- | --- |
| `--target=xtensa` | esp | ok |
| `--target=xtensa --platform=esp` | esp | ok |
| `--target=riscv32 --platform=esp` | esp | ok |
| `--target=xtensa --esp-profile=bare` | none | fails (no RTL — **pre-existing**, pinned fails identically) |
| `--target=riscv32` | posix | ok |
| `--target=x86_64` | posix | ok |
| `--target=riscv32 --platform=posix` | posix | ok |

- **All six esp32 examples build, and the hand-passed `-Fu` now agrees with the
  default byte-for-byte** — `hello-c3` 237648, `timer-c3` 344100, `net-c3`
  380176, `timer-s3` 262683, `hello-s2` / `hello-s3` 186835, identical with and
  without `-Fu`. Per the ticket, those now-redundant `-Fu` lines were **left in
  place**: an explicit override that agrees with the default is not a bug.
  `hello-s2`/`hello-s3` pass no `--platform=esp` at all, so they exercise the
  derivation row specifically.
- `test/lib_platform_esp.pas` builds identically with and without `-Fu` on both
  xtensa (317652) and riscv32 (380992).
- Hosted path unaffected: `uses SysUtils` builds on x86_64 / aarch64 / i386 /
  arm32 / riscv32, and the native binary runs.
- `tools/gate.sh quick`: **GREEN**, all steps including the FPC seed canary.

### Not done — the real-hardware check the ticket asked for

The ticket wants "a real-hardware check" for the riscv32 backend switch. **Not
possible on this box and not done:** no ESP-IDF, no `IDF_PATH`, and no
`qemu-system-*` of any kind (same finding as
[[feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle]]). The esp32
`build.sh` scripts stop at `idf.py`, so only their PXX compile step ran — which
is the step this change affects, but it is object-level evidence, not a booted
image. **Someone with S2/S3/C3 hardware or an IDF install should boot
`examples/esp32/timer-c3` before this is treated as hardware-proven.**

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.
