---
track: A+S
prio: 45
type: bug
blocked-by: []
summary: "AddDefaultPasUnitDirs (compiler.pas) guards the posix PAL search dir on TargetIsEspClass — bare-ness — when the question is which PAL the platform wants. So an ESP-PLATFORM target that is not bare (xtensa under IDF, riscv32 under --platform=esp) gets lib/rtl/platform/posix/ on its unit path, and the esp PAL dir is never added by the compiler at all: every ESP build passes -Fulib/rtl/platform/esp by hand. Latent as of regression-test-emit-obj-cxtensa-obj — nothing on that path pulls the PAL any more — but the guard is still wrong and the next thing to pull platform_backend on an ESP target resolves the posix one."
status: new
owner: ""
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
