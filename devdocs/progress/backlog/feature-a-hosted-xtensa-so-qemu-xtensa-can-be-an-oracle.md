---
slug: feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle
track: A+S
prio: 45
type: feature
blocked-by: []
status: backlog
summary: "xtensa is the one target whose output nothing here can RUN, so every xtensa ticket ends in 'do not land this on inspection'. Stock `qemu-xtensa` (user mode) IS installed, but xtensa has no IR_SYSCALL arm and TargetIsEspClass hardcodes it as bare-metal ALWAYS. Installing ESP-IDF (its qemu fork) is the CHEAPER first move and is worth doing regardless — but it does NOT make the blocked tickets' gates reachable, because those tests need the builtin unit, which no ESP-class target gets."
---

# A hosted xtensa profile, so qemu-xtensa can be an oracle

> **Read this first — two corrections after the box change (2026-08-27).**
> Everything below was measured on **plexus**, the current dev box. plexus
> replaced borg's frank2/frank3 after the 2026-08-20 PSU death, so *"cannot be
> settled on this box"* in [[bug-a-the-div-by-zero-check-is-still-missing-on-xtensa]]
> and its siblings was written about a machine that no longer exists. Whether
> the old box had ESP-IDF is **unknown** — nothing in the tree or in the
> box-level notes records it.
>
> **1. Install ESP-IDF first; it is much cheaper than this ticket.** IDF ships
> the Espressif qemu fork (`qemu-system-xtensa` / `qemu-system-riscv32`), which
> boots a real ESP image, and `test-esp-bare` **already has every row wired**
> behind `if [ -z "$XT" ]; then echo "...not installed; skipped"`. Measured on
> plexus: no `IDF_PATH`, no `~/.espressif`, no `~/esp`, and no
> `qemu-system-*` of ANY kind anywhere on the filesystem — only the stock
> user-mode `qemu-<arch>` binaries. So those rows are all skipping today, and a
> download turns them on. **Do that before doing this.**
>
> **2. But IDF does not unblock the tickets this one was filed to unblock.**
> That was the flaw in the original argument. The gate on
> [[bug-a-the-div-by-zero-check-is-still-missing-on-xtensa]] is
> `test_div_by_zero_raises_on_every_target.pas` producing `ALL OK` under
> xtensa — and that file **cannot be built for an ESP-class target at all**:
>
> ```
> $ pascal26 --target=xtensa  --esp-profile=bare -Fulib/rtl -Fulib/rtl/platform/esp <it>
> error: UpCase: builtin helper unavailable (needs the builtin unit; not on ESP)
> $ pascal26 --target=riscv32 --esp-profile=bare -Fulib/rtl -Fulib/rtl/platform/esp <it>
> error: UpCase: builtin helper unavailable (needs the builtin unit; not on ESP)
> ```
>
> Note the second line: **riscv32-bare fails too**, and riscv32 already has the
> div check landed — because it was verified on the **hosted** profile, which
> gets the full RTL:
>
> ```
> $ pascal26 --target=riscv32 -Fulib/rtl <it> && run_target.sh riscv32 …
> ALL OK
> ```
>
> That is the whole case for this ticket, stated properly: not *"there is no
> emulator"* but *"xtensa is the only target with no HOSTED profile, so the
> cross-differential corpus cannot be built for it, whatever emulator you
> have."* The Espressif fork tests the ESP **product**; a hosted profile tests
> the **backend** against the same corpus every other target runs. They are
> complementary, and only the second makes the blocked gates reachable.
>
> Partial credit where it is due: some cross tests *do* build bare —
> `test_cross_float` does — so the IDF fork would let a subset run. But
> `test_cross_variant` does not either, for an unrelated reason:
> [[bug-a-xtensa-codegen-has-no-variant-support]].


## The problem this exists to remove

xtensa is the only target with **no local execution oracle and no hosted
profile**, and it shows up as a recurring paragraph in ticket after ticket
rather than as one item:

- [[bug-a-the-div-by-zero-check-is-still-missing-on-xtensa]] — *"No local
  oracle... Every other backend's arm was verified by EXECUTING the differential
  under qemu. Do not land this one on inspection."* Five targets got the check on
  2026-08-23; xtensa is still open **only** for this reason.
- [[bug-a-xtensa-cannot-lower-an-int64-to-float-conversion]] — same gate wording.
- Every `test_esp_*` row in the Makefile is *build xtensa, run the x86-64
  oracle*, which proves the compiler does not crash and proves nothing about the
  code it emitted.
- `test-esp-bare`'s real xtensa execution rows are all
  `if [ -z "$XT" ]; then echo "...not installed; skipped"`, and `$XT` is the
  **Espressif qemu fork**, which is not installed on plexus and is not part of
  the base toolchain.

So xtensa work is gated on hardware the box does not have, and the queue behind
it does not move.

## The finding: the emulator is already here

`/usr/bin/qemu-xtensa` — qemu **10.2.1**, Debian `1:10.2.1+ds-1ubuntu3.1`, the
same build whose riscv32/arm/aarch64 user-mode targets every cross differential
in this repo already runs on. `qemu-xtensa -cpu help`:

```
dc232b  dc233c  de212  de233_fpu  dsp3400  lx106  sample_controller  test_mmuhifi_c3
```

`dc233c` carries the windowed register option and the base ISA the backend
emits; `lx106` is the ESP8266 core. This is not the Espressif system-mode fork
and it will not boot an ESP image — it runs a **Linux xtensa ELF** and services
Linux syscalls, exactly as `qemu-riscv32` does for the riscv32 rows.

Nobody appears to have tried it: no ticket in the tree mentions a hosted xtensa,
and `tools/run_target.sh` has no xtensa arm.

## What actually blocks it — measured, both walls hit today

1. **No `IR_SYSCALL` arm.** A minimal program calling `__pxxrawsyscall` builds
   for riscv32 and dies here with `target xtensa: unsupported node in IR codegen:
   syscall`. riscv32's arm (`ir_codegen_riscv32.inc`, `IR_SYSCALL`) is the model:
   marshal into the argument registers, emit the trap, sign-extend the result
   into the 64-bit pair. Xtensa's Linux convention is the syscall number in `a2`
   and arguments in `a6, a3, a4, a5, a8, a9`, result back in `a2` — note that it
   is **not** simply "the argument registers in order", which is the one detail
   worth reading the kernel's `entry.S` for rather than guessing.
2. **`TargetIsEspClass` hardcodes xtensa as bare-metal, always**
   (`util.inc`): `Result := (TargetArch = TARGET_XTENSA) or ((TargetArch =
   TARGET_RISCV32) and EspBareBoot)`. That one predicate is what withholds the
   default RTL, textfile, math and (until 2026-08-27) softfloat from xtensa. A
   hosted xtensa has to become the same kind of dual-role target riscv32 already
   is — `--platform=posix --target=xtensa` meaning a Linux ELF, `--platform=esp`
   keeping today's behaviour — and the comment on `TargetIsEspClass` already
   says why writing that test out by hand is a trap. There are **68**
   `TARGET_XTENSA` mentions outside the backend files; most are ISA facts, but
   they need reading, and `util.inc`'s comment already flags which of the
   look-alike spellings must NOT be collapsed.

Without the profile flag, `--target=xtensa` alone defaults to ESP-IDF and stops
at `external (dynamic) symbols are not supported on this target (first one:
calloc)`.

## Why it is worth it

The riscv32 half of ESP is verifiable and the xtensa half is not, and **xtensa is
the user's primary S target** (the S2/S3 hardware) while riscv32 is the one that
merely works today. Every xtensa arm landed so far — atomics, call0 large
frames, the softfloat kernels — rests on an x86-64 oracle plus inspection. The
one thing that would change that is already installed.

Same shape as the argument in `devdocs/dev/debugging-playbook.md`: reasoning was
cheaper than measuring, so reasoning won, and the way out is to make measuring
possible.

## Scope note

This is Track A machinery with a Track T payoff, and it should land in that
order: (1) `IR_SYSCALL` + a posix xtensa profile, (2) an xtensa arm in
`tools/run_target.sh`, (3) promote the `test_esp_*` rows from *build-only* to
*differential*, (4) then the blocked tickets above become ordinary work. Steps
1-2 alone are the whole unblock; 3-4 are the harvest and can be separate
tickets.

## Gate

`qemu-xtensa` running a hosted xtensa `writeln` and matching the x86-64 oracle;
`tools/run_target.sh xtensa` working; and at least one existing cross
differential (e.g. `test_cross_float`) promoted from skipped/build-only to
green on xtensa. Track A's usual gate on top.

## Found by

Reaching for an oracle while scoping
[[bug-a-xtensa-cannot-lower-an-int64-to-float-conversion]] and
[[bug-a-the-div-by-zero-check-is-still-missing-on-xtensa]], both of which say
in prose that no xtensa emulator is available here. One of them is.
