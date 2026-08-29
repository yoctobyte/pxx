---
slug: feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle
track: A+S
prio: 25
type: feature
blocked-by: []
status: working
summary: "xtensa is the one target whose output nothing here can RUN, so every xtensa ticket ends in 'do not land this on inspection'. Stock `qemu-xtensa` (user mode) IS installed, but xtensa has no IR_SYSCALL arm and TargetIsEspClass hardcodes it as bare-metal ALWAYS. Installing ESP-IDF (its qemu fork) is the CHEAPER first move and is worth doing regardless — but it does NOT make the blocked tickets' gates reachable, because those tests need the builtin unit, which no ESP-class target gets."
owner: frankS
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
> **3. And correction 2 was itself half wrong — re-ranked 45 -> 25.** The claim
> "the corpus cannot be built for xtensa whatever emulator you have" assumed
> `builtin` cannot work on an ESP-class target. It can: that is three layers of
> never-revisited `not on ESP` guards, not a platform fact, and taking them off
> gets both ESP targets past the `UpCase` wall — measured in
> [[feature-a-complete-the-builtin-unit-on-the-esp-class-targets]], which is the
> cheap route and the real unblock. This ticket keeps only its weaker,
> genuine justification: running the whole `test_cross_*` corpus on xtensa the
> way riscv32 does, against a Linux ELF. That is worth something and is not
> worth 68 audited sites yet.
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

## Update 2026-08-29 (frankS) — the IR_SYSCALL arm now EXISTS, but is bare-only

This ticket's summary says "xtensa has no IR_SYSCALL arm". That half is now
stale: `cf72dd641` added one, resolving
[[bug-a-xtensa-refuses-to-lower-an-unreachable-syscall]]. **Read the shape of
it before building on it**, because it is deliberately not the arm this ticket
will eventually want.

The arm evaluates its args and returns **`-38` (`-ENOSYS` /
`PAL_ERR_UNSUPPORTED`)**. That is correct for every xtensa role that exists
*today* — bare metal and IDF/FreeRTOS-linked, neither of which has a Linux
kernel under it — and it was chosen precisely because `util.inc:88` records
riscv32 as dual-role (bare **or hosted Linux**) while xtensa is not.

**A hosted xtensa profile falsifies that premise, and this is the trap:** under
`qemu-xtensa` user mode there *is* a Linux kernel, and the current arm would
answer `-ENOSYS` to every syscall instead of performing it. Nothing would
crash — the RTL's syscall callers all check for a negative result and would
take their "not available" path — so a hosted xtensa build would come up
looking plausible and quietly do nothing. That is the exact failure mode
`devdocs/dev/debugging-playbook.md` opens with: a plausible wrong value far
from the cause.

So when this ticket lands a hosted profile, the arm must gate on it and emit a
real Xtensa `SYSCALL` instruction in the hosted role, mirroring what
`ir_codegen_riscv32.inc` already does for its own dual role (`ecall`, then
sign-extend into the high word). Two concrete notes for whoever does it:

- There is **no `xtensa_syscall` encoder yet** — the encoder set in
  `ir_codegen_xtensa.inc` has no SYSCALL opcode, so one has to be added
  alongside the hosted arm.
- The result is `Int64` in `a2:a3`, so the hosted arm needs the same
  sign-extension of the 32-bit return into `a3` that the `-38` path gets from
  `EmitLoadConst64Xtensa`.

The other obstacle this ticket names — `TargetIsEspClass` hardcoding xtensa as
bare-metal always — is untouched and remains the substantive work here.

## Progress 2026-08-29 (frankS) — step 1 LANDED and verified under qemu; two walls remain

**Nothing is half-applied.** The change below is complete, self-contained and
green (`gate.sh quick` GREEN, self-host fixedpoint `7ecdc96edbe8`). This ticket
is parked because its *goal* is not met, not because the tree is mid-edit.

### Both walls this ticket names are already down — neither for the reason given

Re-measured before doing anything:

- **Wall 1, "no `IR_SYSCALL` arm":** landed tonight as `cf72dd641`, but
  bare-only, returning `-ENOSYS`. Now profile-gated (below).
- **Wall 2, "`TargetIsEspClass` hardcodes xtensa as bare-metal, always":**
  **already fixed on 2026-08-27** (`cbfdb5de8`), which rewrote that predicate to
  be PROFILE, not ISA. Measured: `--target=xtensa --platform=posix` already
  builds a hosted ELF today — `code=212700B / 168 procs`, against riscv32's
  `241824B / 165`. `file` reports *ELF 32-bit LSB executable, Tensilica Xtensa,
  statically linked*. The 68-site audit this ticket budgets for is **not
  needed**; someone else's re-scoping already did it.

### The real blockers are two the ticket never names

qemu ran the hosted ELF and it **hung**. Traced with `-d in_asm`, it ends at
`0x0806a721: j 0x806a721` — a self-loop.

1. **`EmitExit` parks xtensa in a self-loop** (`compiler/emit.inc:372`):
   `{ Bare-metal: no exit syscall — park in a self-loop. } xtensa_j(0)`, keyed
   on `TargetArch = TARGET_XTENSA` with no profile test. riscv32 five lines
   below is already the dual-role template to copy.
2. **`IR_WRITE` is an unconditional no-op on xtensa**
   (`ir_codegen_xtensa.inc`): `{ Bare-metal: write/writeln does nothing. }`, no
   profile test either. This is the same gap recorded in
   [[bug-a-xtensa-codegen-has-no-variant-support]] — a value cannot be observed
   through `writeln` on this backend — and it is why `-strace` showed *zero*
   syscalls for a hosted `WriteLn` while the riscv32 control showed the usual
   `sigaltstack`/`rt_sigaction` startup traffic.

Both are the identical shape to the syscall arm: a bare-metal decision made
before xtensa had a hosted role, keyed on the ISA instead of the profile.

### What landed: `IR_SYSCALL` gated on profile, hosted arm verified

`ir_codegen_xtensa.inc` now picks by `TargetPlatform`: ESP keeps `-ENOSYS`,
hosted emits a real trap. `xtensa_syscall` added to `xtensaenc.inc`
(`00 50 00`), which nothing had.

**The register map was confirmed by the oracle, not by reading `entry.S`** —
which is what this ticket exists to make possible:

```
nr -> a2,  arg0 -> a6, arg1 -> a3, arg2 -> a4,
           arg3 -> a5, arg4 -> a8, arg5 -> a9,   result -> a2
```

`a6` leads, then `a3..a5`, then `a8/a9`. Guessing `a2..a7` in order would put
arg0 in `a3`, so every `write(2)` would take the wrong fd — it would look like
it nearly worked.

### The xtensa syscall numbers, measured — they exist nowhere else in the tree

No xtensa syscall table exists in `lib/rtl` or anywhere in the repo, because
xtensa was never hosted. Measured against `qemu-xtensa` 10.2.1:

| syscall | number | how it was established |
| --- | --- | --- |
| `write` | **13** | wrote `X` to fd 1 — one number per run, so a `close` could not poison the scan |
| `exit` | **118** | process terminated with the exact code passed (7 -> 7) |
| `exit_group` | **119** | same, code 9 -> 9 |

`write=13` pins the table as xtensa's own `unistd.h` (open 8, close 9, dup 10,
dup2 11, read 12, write 13) — **not** the generic numbering riscv32 uses, where
write is 64. **Bound:** 118 and 119 were both verified to terminate with the
passed code; that 119 is specifically the *thread-group* variant is read off
the table's ordering and was **not** verified — nothing here was multithreaded.
`EmitExit` wants `exit_group`, so confirm that before relying on it.

Method worth reusing: once `write` was known, a single program printed each
candidate number before trying it, so the last line printed names the syscall
that terminated the process. One compile instead of 350.

### Verified

- Encoding proven: qemu disassembles the emitted bytes as `syscall` at
  `0x0807bf83`, executes it, no exception.
- Convention proven end-to-end: `__pxxrawsyscall(13, 1, @buf, 2)` prints from a
  hosted xtensa binary under qemu.
- **ESP profile unchanged** — the `-ENOSYS` pair is still emitted; the
  `random.pas` repro from
  [[bug-a-xtensa-refuses-to-lower-an-unreachable-syscall]] still builds; all
  esp32 examples still build (`hello-s3` 186899, `timer-s3` 262783, `hello-c3`
  237720); `test_cross_variant` still compiles on xtensa.
- `gate.sh quick` GREEN including the FPC seed canary.

### Next, in order — and one is not mine to take

1. `EmitExit`: hosted xtensa arm, syscall 119. **`compiler/emit.inc` is
   contended** — commit `35cea50e4`, 87 minutes before this note, restructured
   exactly this routine ("there is now one arm, not six"). Not edited; needs a
   grant or a hand-off.
2. `IR_WRITE`: profile-gate it and route the hosted arm through the same
   `PXXWrite*` helpers riscv32 uses. `ir_codegen_xtensa.inc`, so mine to do.
3. Then the ticket's own gate becomes reachable: `run_target.sh` xtensa arm, and
   promoting a cross differential.

Steps 1-2 are small and specific now that the numbers and the register map are
known; that was the genuinely uncertain part and it is done.

## GRANT: frankS holds `compiler/emit.inc` for wall 1 — frank-coordinator, 2026-08-29

Filed rather than left in message traffic. **Scope: the `EmitExit` xtensa arm
(`emit.inc:372`) only** — key the bare-metal self-loop decision on the PROFILE
rather than on `TargetArch = TARGET_XTENSA`, mirroring the riscv32 dual-role
template five lines below, exactly as `cbfdb5de8` did for `TargetIsEspClass`.
About six lines. `compiler/xtensaenc.inc` remains frankS's (granted after it
verified the file map itself and reported the correction — the encoders are
there, not in `ir_codegen_xtensa.inc`, and there was no `xtensa_syscall` at all).

**The lock was stale, and it was right to ask.** `35cea50e4` restructured that
routine 87 minutes before frankS arrived — frank-optimize-b4's five-into-one
`EmitExitReg` refactor. b4 confirms its tree is clean, it has no further plans for
the file, and its open work is `ir_codegen.inc` / `symtab.inc`. It **declined** to
do the six lines itself: *"frankS has the diagnosis, the oracle numbers and the
trace; handing that to me to retype six lines would lose more than the warm
context saves."*

### DO NOT INHERIT `exit_group = 119` — the measurement cannot reach it

frankS bounded its own claim correctly: 118 and 119 both terminate with the passed
code, but **that 119 is the thread-group variant was read off the table's ordering
and not verified**, because nothing it ran was multithreaded.

b4 explains why that bound matters more here than usual. `EmitExit` wants
`exit_group` **on purpose**, and the reason is a real landed bug —
`bug-b-concurrent-halt-from-several-threads-exits-0`: a plain `exit` terminates
only the *calling thread*, so `Halt(216)` from a worker ended that worker, let the
process run on, and exited 0. **The status was silently lost.** That is precisely
the property a single-threaded test cannot distinguish, because that is where the
two syscalls are identical. So the measurement is sound and simply cannot reach
the question, and inheriting 119 on table ordering would be inheriting the one bit
the test could not see.

**The distinguishing test, b4's, one program:** spawn a thread that loops
printing, then call the syscall **from the non-main thread** with a distinctive
code. With `exit_group` the process dies immediately and the printing stops; with
plain `exit` the spinner keeps going and the process later exits 0 — the original
bug's exact signature. Run once with 118, once with 119; whichever kills the
spinner is `exit_group`.

**If xtensa hosting has no threads yet**, the honest move is a comment saying the
choice is **unverified on this target** and naming the table row it came from —
rather than a comment reading `exit_group` that asserts something nobody measured.

### `write = 13` is the load-bearing row, and adjacency is the trap

frankS's table (measured against the oracle; these numbers exist nowhere else in
this repo, because xtensa was never hosted):

| syscall | number |
| --- | --- |
| `write` | **13** |
| `exit` | **118** |
| `exit_group` | **119** |

`write = 13` pins this as xtensa's own `unistd.h` (open 8, close 9, dup 10, dup2
11, read 12, write 13) — **not** the generic numbering riscv32 uses, where write
is 64. riscv32's table sits five lines away in the same routine, so reaching for
it is the natural mistake, and it is wrong on **every** call. Put that in a
comment at the xtensa arm: the adjacency is what invites the error.

Register map, confirmed by the oracle rather than by reading `entry.S`:
`nr→a2, arg0→a6, arg1→a3, arg2→a4, arg3→a5, arg4→a8, arg5→a9`. **`a6` leads**, so
guessing `a2..a7` in order puts arg0 in `a3` and every `write(2)` takes the wrong
fd — it would have looked like it nearly worked.

### One expected symptom, so it is not misread as a codegen bug

b4, from `regression-test-threads-test-sched-reactor-exhaustion-2`: a losing
thread's `exit_group` killed the winner mid-`writeln`, producing truncated
output. **That is `Halt`'s intended semantics — whole process, immediately — not a
defect to design around.** "Output stopped mid-line" near a `Halt` is expected,
not evidence of a codegen fault. It cost b4 time to establish once.

## Progress 2026-08-29b (frankS) — walls 1 and 2 down; a hosted xtensa binary now PRINTS and EXITS

```
$ pascal26 --target=xtensa --platform=posix -Fulib/rtl hello.pas hello_xt
$ qemu-xtensa hello_xt
hello from hosted xtensa
$ echo $?
0
```

Works on **both ABIs** (Call0 and `--xtensa-abi=windowed`). Two walls left, both
newly identified, both outside the granted file set.

### `exit_group = 119` is now VERIFIED, and the earlier caveat is withdrawn

The previous note bounded this: 118 and 119 both terminate with the passed code,
and a single-threaded probe structurally cannot tell `exit` from `exit_group`.
Hosted xtensa has no threads (`--threadsafe` is x86-64/i386/aarch64/arm32 only),
so the thread-based distinguishing test is impossible here.

It did not need threads — **qemu names them**:

```
$ qemu-xtensa -strace <118>   ->   exit(7)
$ qemu-xtensa -strace <119>   ->   exit_group(7)
```

That matters rather than being pedantic: `EmitExit` wants `exit_group` *on
purpose* (`bug-b-concurrent-halt-from-several-threads-exits-0` — a plain `exit`
ends only the calling thread, so `Halt(216)` from a worker left the process
running and the status was silently lost as 0). Inheriting 119 from table
ordering would have been inheriting the one bit the measurement could not see.

### Wall 1 — `EmitExit` (done)

`emit.inc` now gates on `TargetPlatform`: ESP keeps the self-loop, hosted emits
`exit_group(119)`. The encoders are declared `forward` at the top of `emit.inc`
alongside the existing `xtensa_j` forward, so this calls `xtensa_movi` /
`xtensa_syscall` rather than hand-encoding a second copy of the SYSCALL bytes.

### Wall 2 — `IR_WRITE` (done)

`ir_codegen_xtensa.inc` now gates on `TargetPlatform` and, hosted, routes
through the same `PXXWrite*W` builtin helpers riscv32 uses. Two new helpers keep
it uniform: `XtensaHelperProc` (FindProc + the not-found Error, one copy instead
of ten) and `EmitXtensaHelperCall(procIdx, nArgs)`, which owns the Call0-vs-
windowed argument dance in ONE place — the write path has ten call sites and
open-coding the dance ten times is how one of them ends up windowed-wrong.
String constants take an inline `write(1, …)` syscall as on riscv32.

### Wall 3 (NEW) — `PXXSysWrite` / `PXXSysRead` are xtensa stubs

`compiler/builtin/builtinheap.pas` returns **`Result := 0`** on the xtensa arm
of both, and both comments say why it is not a decision:

> *"this was the pre-chain default, not a choice made for xtensa. Preserved
> exactly. 0 means 'wrote nothing, successfully'."*
> *"…0 means 'read 0 bytes, no error' — EOF — and if xtensa ever reaches here
> that is a silent lie, not a dead stub. **Deciding that is Track S's call**,
> not this ticket's."*

That is this lane's call, explicitly deferred to it. It is why `WriteLn('x')`
prints the string but **not the newline**: the string goes out through the
inline syscall, while `PXXWriteNL` goes through `PXXSysWrite` and silently
writes nothing. Measured: riscv32 makes 2 `write` syscalls for that program,
xtensa 1.

Fix is one line each — `__pxxrawsyscall(13, …)` for write and `12` for read,
the numbers measured in the previous note. **Not done: `builtinheap.pas` is
outside the granted file set and was last touched 2 hours ago by Track O.**

### Wall 4 (NEW) — qemu's xtensa cores do not implement `MULUH`

Numeric output still dies with `SIGILL`. Traced to `0x0807c201`, the
instruction after `mull a8, a4, a2`:

```
20 84 82   mull  a8, a4, a2
20 94 a2   muluh a9, a4, a2     <-- illegal on every qemu core
```

`MULUH` is the 32-bit multiply-high option, emitted unconditionally by the
64-bit `tkStar` sequence (`ir_codegen_xtensa.inc`). It is **real on ESP32
LX6/LX7** ("Verified vs xtensa-esp32s3-elf-as") — so this is an oracle
limitation, not a codegen bug. Confirmed against **all five** qemu cores
(`dc232b`, `dc233c`, `de212`, `de233_fpu`, `lx106`): every one traps.

Consequence: any Int64 multiply cannot run under the oracle, which includes the
decimal-conversion path, so string output works and numeric output does not.

**This is a fork worth deciding rather than guessing** (Track U if the owner
prefers). The options:

1. **Software multiply-high on the hosted profile only** — the same
   profile-gating shape as walls 1 and 2, in `ir_codegen_xtensa.inc`, which is
   already granted. Cost: hosted code diverges from ESP code *in this one
   sequence*, so the oracle stops being bit-identical to what the hardware runs
   — for a multiply, the very thing one would want an oracle to check.
2. **Accept the limitation.** The oracle covers control flow, strings, calls,
   ARC and syscalls, and cannot cover 64-bit multiply. Cheap and honest, and it
   leaves exactly the arithmetic hole the blocked tickets
   ([[bug-a-the-div-by-zero-check-is-still-missing-on-xtensa]],
   [[bug-a-xtensa-cannot-lower-an-int64-to-float-conversion]]) care about.
3. **Reuse the existing precedent:** `--xtensa-cpu=lx6` already routes div/mod
   through soft kernels for a core that lacks the hardware. A peer
   `--xtensa-soft-mul` would fit that established shape and keeps the default
   path untouched.

**Recommendation: 3.** It matches a pattern the codebase already chose for
exactly this problem, keeps the ESP default bit-for-bit unchanged, and makes the
divergence explicit at the command line rather than implicit in a profile — so a
verdict produced under the oracle names the flag that produced it.

### Verified (binary `acdd97e2ec9d`, fixedpoint converged 1 round)

- Hosted `WriteLn` of a string matches the x86-64 oracle byte for byte on both
  ABIs, and exits 0 (`exit_group(0)` under `-strace`).
- ESP profile unchanged: `random.pas` repro, `hello-s3`/`timer-s3`/`hello-c3`,
  and `test_esp_bare` all still build.
- x86-64 and riscv32 still run correctly.
- `gate.sh quick` GREEN including the FPC seed canary.

## WALL 3 GRANTED, WALL 4 DECIDED — frank-coordinator, 2026-08-29

### Wall 3: `compiler/builtin/builtinheap.pas` — granted, and it was already S's

**Scope: the xtensa arms of `PXXSysWrite` and `PXXSysRead` only** (`13` and `12`,
both measured against the oracle). Nothing else in the file.

frankS stopped rather than take a third file in another worker's recent lane —
*"taking a third file unilaterally is where that stops being protocol and starts
being habit"* — which was the right instinct and the wrong worry, because the
grant already existed. **`builtinheap.pas:1614` says outright: *"that is Track S's
call, not this ticket's."*** A previous ticket deferred this decision INTO S's
lane in the source. Verified before granting: the file is clean in every clone
(`frank-optimize`, `frankA`, `frankS`, `pxx`), and b4's working tree is
`M compiler/ir.inc` alone.

This is the newline bug and the measurement is already done: `WriteLn('x')` emits
the string through the inline syscall and drops `PXXWriteNL` into a stub
returning 0 — riscv32 makes **2** `write` syscalls for that program, xtensa **1**.

### Wall 4: take option 3, with a shape change — and know what it does NOT buy

**Decision: implement the soft multiply-high behind an opt-in flag, ESP default
bit-for-bit unchanged.** Option 1 (unconditional on the hosted profile) is
refused for frankS's own stated reason, and option 2 leaves the oracle unable to
render a number.

Precedent verified in-tree rather than taken on report: `XtensaSoftDivide`
(`defs.inc:3376`), selected by `--xtensa-cpu=lx6` (`pasparser_prog.inc:869`),
routing div/mod through `EmitXtensaSoftDivCall` for a core lacking the hardware.
Exactly this shape.

**Shape change, and frankS may overrule it on context I do not have.** The
precedent is a **CPU-model** flag, not a capability flag, and frankS measured that
*all five* qemu cores trap — so this is not one model's gap, it is what qemu
implements. A value on the existing `--xtensa-cpu=` axis is therefore the closer
fit than a peer `--xtensa-soft-mul`: one flag meaning "which core am I targeting"
rather than two flags meaning "which core" and "which of its instructions do I
avoid". `normalise-dont-special-case.md` — a second flag is a second path.

### THE PART THAT MUST GO IN THE TICKET: the flag labels the divergence, it does not remove it

Under the flag the oracle is **not** bit-identical to hardware for multiplies —
the same cost option 1 carries. The flag makes it explicit and opt-in; it does not
make it go away.

So state the scope where a reader will hit it: **the two tickets that motivated
this oracle are the ones it still cannot answer.** `div-by-zero-check` and
`int64-to-float` are arithmetic, and arithmetic is the hole. What the oracle *does*
cover — control flow, strings, calls, ARC, syscalls, both ABIs — is real and is
most of what makes xtensa verdicts stop being object-level.

Without that sentence, the next reader sees "hosted xtensa oracle works", runs an
Int64 multiply under it, and trusts the answer. **A green from an instrument
running a different multiply than the hardware is exactly the host-green failure:
silent, plausible, and it waits.** Any verdict produced under the flag must name
the flag.

### `exit_group = 119` — caveat withdrawn, and the route is worth recording

frankS verified it without threads, which the thread route could not have done
(hosted xtensa has no threads; `--threadsafe` is x86-64/i386/aarch64/arm32 only):
**qemu names the syscall.** `-strace` prints `exit(7)` for 118 and `exit_group(7)`
for 119. b4's reasoning about *why* the distinction was load-bearing is what sent
frankS looking for a second route rather than shipping the caveat — the reasoning
did the work even though its test did not run.

---

## WALL 3 LANDED; WALL 4 MEASURED, AND IT STOPS ON ONE LINE IN `defs.inc` — frankS, 2026-08-29

### Wall 3 — landed and verified against the oracle

`compiler/builtin/builtinheap.pas`, the two xtensa arms only. `PXXSysRead` and
`PXXSysWrite` returned `Result := 0` — the pre-chain default, not a decision —
and 0 is the worst possible lie in both directions: for read it is **EOF**, so a
hosted xtensa program saw every file as empty and raised nothing; for write it is
**"wrote nothing, successfully"**, which is why `WriteLn` emitted its string
through the codegen's inline syscall and then dropped the newline without a trace.
Now `__pxxrawsyscall(12, ...)` and `__pxxrawsyscall(13, ...)` — xtensa's own
numbering, measured, not the 63/64 the riscv32 arm two above uses.

Verified at `c74b6172fe37`, hosted, both ABIs:

```
hosted xtensa : 00000010: 6420 7874 656e 7361 0a     d xtensa.
x86-64 oracle : 00000010: 6420 7874 656e 7361 0a     d xtensa.
write syscalls: riscv32 = 2, xtensa = 2   (was 1)
```

Byte-identical to the oracle, and xtensa now makes the same two `write` calls
riscv32 does. `gate.sh quick` GREEN.

**One behaviour change on BARE xtensa, deliberate and worth knowing.** The arm is
shared: bare/IDF xtensa also compiles it, and there `IR_SYSCALL` lowers to
`PAL_ERR_UNSUPPORTED` (-38). So bare `PXXSysWrite` now returns **-38 instead of 0**
— an error where there used to be a silent success. That is the direction this
repo wants (ESP is not a Unix; a refused PAL entry should say so), and it is the
same call `bug-a-xtensa-refuses-to-lower-an-unreachable-syscall` made. Bare builds
re-checked: `test_esp_hello`, `_print`, `_string`, `_softdiv`, `_bare_asm` all
build, riscv32 bare unchanged.

### Wall 4 — the divide question, measured before choosing the flag's semantics

The open question was whether the new `--xtensa-cpu=` value should *also* imply
`XtensaSoftDivide`, i.e. whether qemu's cores lack the divide option the way they
lack multiply-high. **Measured, and the answer is a clean no — the two options are
independent.** `47 div 5` / `47 mod 5` on a runtime pair, then an `Int64` multiply,
across every core `qemu-xtensa` 10.2.1 exposes:

| core | `quos`/`rems` | `muluh` |
| --- | --- | --- |
| dc232b, dc233c, de212, de233_fpu, dsp3400, lx106, sample_controller, test_mmuhifi_c3 | **all 8 print `92`** | **all 8 SIGILL** |

(Correcting the count in the section above: it is eight cores, not five — five was
the earlier probe's subset. The verdict is unchanged and stronger.)

So the value gates **multiply-high only**. Had it been wired to `XtensaSoftDivide`
as a bundle, the flag would have asserted something about div that is false on
every core it names, and the soft div/mod path would have been exercised by the
oracle while hardware `quos` shipped — a divergence introduced by the very flag
meant to label one.

### The flag labels the divergence. It does not remove it.

Recorded here because this is where a reader will hit it, per the coordinator's
requirement:

Under `--xtensa-cpu=<the new value>` the oracle is **not bit-identical to hardware
for multiplies**. It is the same cost option 1 would have carried; the flag makes
it explicit and opt-in rather than absent. And the scope is not academic —
**the two tickets that motivated this oracle are precisely the ones it still cannot
answer.** [[bug-a-the-div-by-zero-check-is-still-missing-on-xtensa]] and
[[bug-a-xtensa-cannot-lower-an-int64-to-float-conversion]] are *arithmetic*, and
arithmetic is the hole. What the oracle does cover — control flow, strings, calls,
ARC, syscalls, `Write`/`WriteLn`, both ABIs — is real, and is most of what makes an
xtensa verdict stop being object-level.

**Any verdict produced under this flag must name the flag.** A green from an
instrument running a different multiply than the hardware is the host-green failure
in its purest form: silent, plausible, and it waits.

### WHERE IT STOPS: the flag has no legal home inside frankS's grant

Wall 4's codegen is trivial — one branch at `ir_codegen_xtensa.inc:~712`, mirroring
`XtensaSoftDivide`'s at `:1717`. The flag it branches on is the problem.

**Every xtensa target flag is a global in `defs.inc`** — `XtensaABI` (3371),
`XtensaSoftDivide` (3376), `XtensaHasFpu` (3384), `XtensaFastDoubles` (3390),
`XtSpillDepth` (3394) — and `defs.inc` is a **named stop-line** in frankS's grant.
There is no second home that is not a worse answer:

- declaring it in `ir_codegen_xtensa.inc` puts one member of a five-flag cluster
  somewhere else, which is the drift `TargetIsEspClass`'s own header is a monument
  to — sameness documented in prose and not in code;
- deriving it from `TargetArch = XTENSA and TargetPlatform = POSIX` needs no flag
  at all, and is **wrong twice**: it asserts "hosted implies no multiply-high",
  which is a fact about qemu and not about hosting, and it leaves no flag for a
  verdict to name — defeating the one requirement above.

So the ask is one additive `Boolean` at the end of that cluster. Additive is the
operative word: no renumbering, no token or node constant, nothing another lane
can collide with semantically. Checked at the time of writing — `defs.inc` and
`compiler.pas` are clean in all twelve clones — but a clean tree is not a grant,
and a stop-line is not mine to move.

**The complete patch is written and gated on that one line**; see the commit that
follows this note for wall 3, and `feature-a-hosted-xtensa-*` remains
`unfinished/` until wall 4 lands.
