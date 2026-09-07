---
slug: bug-a-errno-is-one-global-across-all-threads-so-a-thread-reads-another-threads-failure
title: "errno is one global across all threads, so a thread can read another thread's failure code"
track: A
prio: 65
type: bug
status: backlog
created: 2026-09-04
found-by: franks-ab
owner: ""
blocked-by: []
summary: "MEASURED, reproduced independently by two sessions: a threaded pxx C program shares ONE errno across all threads, where C requires it thread-local. Two threads provoking different errors and reading errno on the very next line see each other's codes 4-84 times per 200000 iterations, varying per run as a race should; the gcc/glibc oracle is 0 every time. --threadsafe does NOT fix it -- that flag selects a real thread PAL and threads genuinely run, so the one flag a reader would expect to cover this is the one that silently does not. Root: lib/crtl/include/errno.h:5 declares `extern int errno;` (an ordinary int) where glibc has `#define errno (*__errno_location())`; the tentative definition becomes a WEAK non-TLS .bss object in every pxx object file. The visible symptom is a static-link refusal (ld: TLS vs non-TLS mismatch against libc.a), but that is the LUCKY case -- it stops and names the symbol. The dynamic link tolerates the mismatch and nothing errors anywhere. CORRECTED 2026-09-07 -- THE ROOT IS ONE SHARED FS BASE, NOT A ZERO ONE, and a fix controlled on "no longer zero" passes while still broken: a probe that imports anything from the system C library measures a NON-ZERO base that is nevertheless IDENTICAL in main and child (ld.so installs a TCB for the main thread; pxx's clone stub installs none, so the child inherits it), while the same probe using a raw syscall reads 0 in both. Assert DISTINCT PER THREAD, never non-zero. CLONE_SETTLS is not in PXX_CLONE_THREAD ($350F00, decoded with residue 0) and AN_CLONE has no `tls` parameter to pass one, so the real-TLS path costs a compiler intrinsic's arity and not a constant. Earlier wording, still true of the no-libc configuration: pxx programs run with FS BASE ZERO in every thread (arch_prctl(ARCH_GET_FS) rc=0 value=0 in the main thread AND in a pthread_create'd one, against distinct non-zero values under glibc, sentinel-controlled so a failed syscall is not read as a zero base), so an fs-relative access resolves every thread to the same place and a .tbss section would only make it LOOK repaired. SUPERSEDED 2026-09-07 -- THE PER-THREAD BLOCK ALREADY EXISTS AND EVERY READING ABOVE MEASURED THE WRONG REGISTER: pxx's TLS is GS-relative. Five threads show five DISTINCT gs bases (main 0x45acb8 plus four stack-carved blocks) while fs is 0 in all of them; glibc is the mirror image. defs.inc already has TLS_SLOT_FIRST_FREE = 13 with three free slots and __pxxTlsBase already returns the calling thread's block, so the fix needs no CLONE_SETTLS, no AN_CLONE parameter, no .tbss and no gettid on the error path -- errno simply never went into the storage that exists. The real constraint is the TARGET SET: __pxxTlsBase refuses off x86-64 while --threadsafe covers four targets and this ticket's own table has i386 racing 21/26, and it fixes no FOREIGN thread on any target because one that libc created never runs the clone stub that carves the block. There is also a cheaper path that skips ELF TLS entirely -- glibc's own header is `#define errno (*__errno_location())` and crtl's pthread.c already keeps a tid-keyed registry -- whose open question is how to find the slot without TLS (__pxx_pthread_self is not linked without --threadsafe; gettid(2) per access puts a syscall on every error path). That path closes THIS ticket and not [[bug-c-__thread-is-accepted-and-silently-ignored-so-thread-local-storage-is-shared]], the general form: __thread is in cparser.inc's tolerate-by-skipping set, so thread-local storage is silently shared for every variable, not just errno. Reproduced a third time at 1b903c1dd with a third probe: 33 and 4."
---

# errno is one global, not one per thread

## The measurement

The probe asserts a RELATION, not a constant — *"a thread only ever sees the
errno its own call produced"* — so it carries no per-platform value and is
correct against any libc. Two threads, 200000 iterations each: thread A calls
`open()` on a missing path (`ENOENT`), thread B calls `close(-1)` (`EBADF`),
and each reads `errno` back on the very next line and counts how often it sees
the *other* code.

| build | thread A wrong | thread B wrong |
| --- | --- | --- |
| gcc / glibc (oracle) | 0 | 0 |
| pxx x86-64 `--threadsafe`, pinned v403 `c31d03b2` | 4 | 84 |
| pxx x86-64 `--threadsafe`, `1968c7a7da57` (frankD, 3 runs) | 8 / 21 / 6 | 12 / … / 8 |
| pxx **i386** `--threadsafe`, `1968c7a7da57` (frankD) | 21 | 26 |

Nonzero every run, varying as a race should. glibc is 0 every run. Reproduced
independently by franks-ab and frankD, on different compiler builds, with
separately written probes.

**One of the two readings used the PINNED v403 compiler**, which rules out "this
landed after the pin" — the one alternative explanation available. Two readings
that could have failed the same way would have been one reading.

**It is WIDTH-INDEPENDENT (i386 row above), and that is an acceptance
constraint rather than a curiosity.** `extern int errno;` is a 4-byte int at
both widths and TLS-versus-not is orthogonal to pointer size, but orthogonal in
principle is not a measurement and now it is one. The usual hazard in this repo
is the opposite one — width and alignment bugs being structurally invisible on
the x86-64 host that the dev loop, `gate.sh quick` and the pin all run on. Here
the bug is present at BOTH widths, so the risk is symmetric: **a fix verified
only on the host would look complete.**

**The rate is a FLOOR, not an estimate.** Both probes read `errno` on the very
next line, so the window is a few instructions. Real code does work between the
failing call and the check — a log line, cleanup, another call — and the window
scales with that work. Do not quote 0.004% as the exposure.

## Root cause

`lib/crtl/include/errno.h:5`

    extern int errno;

an ordinary `int`, where glibc has `#define errno (*__errno_location())` and C11
7.5 requires `errno` to be thread-local. The tentative definition becomes a weak
non-TLS object in every translation unit:

    pxx object   errno  OBJECT WEAK  4 bytes, section .bss   (non-TLS)
    glibc        errno  TLS GLOBAL   4 bytes                 (.tbss)

## Why the linker error is the good half

Static linking REFUSES the mismatch outright:

    ld: errno: TLS definition in libc.a(errno.o) section .tbss
        mismatches non-TLS definition in obj/coreutils_cat.o section .bss

That is the lucky case: it stops, it names the symbol, and the fix is forced.
**The dynamic link tolerates it**, which is the expensive outcome — every
threaded pxx program that reads `errno` after a failing call can read a value
another thread wrote in between, with nothing erroring anywhere. `errno` is
close to the worst variable for this: it is read immediately after a failure and
branched on, so a corrupted read becomes a wrong control-flow decision far from
its cause.

## `--threadsafe` does not cover it, and that is part of the bug

Without the flag the compiler refuses, and the refusal is a good one:

    __pxx_pmutex_init needs the thread-safe runtime: rebuild with --threadsafe
    (<pthread.h> lowers onto the pxx thread PAL, which that flag selects)

So the flag exists, it selects a real thread PAL, and threads genuinely run —
`lib/crtl/src/pthread.c:108` implements `pthread_create` over
`__pxx_pthread_create`. The flag a reader would expect to make threading correct
is exactly the one that leaves `errno` shared, so nobody gets a warning.

## Repro

    ./stable_linux_amd64/default/pinned --threadsafe errno_race.c out && ./out
    gcc -O1 -o oracle errno_race.c -lpthread && ./oracle     # the oracle

Probe source: see the table above for the shape; it is ~40 lines and asserts
only the relation, so it needs no expected constants.

## Acceptance — a row per target, not one green on the host

If the repair grows TLS symbols in the emitter, **each backend has to grow them
separately**, so one green on x86-64 does not close this. The acceptance wants a
row for every target with an object writer.

**Assert the RELATION the probe already asserts — zero foreign errno values —
never a per-target constant.** It passes everywhere, needs no expected value,
and therefore cannot be satisfied by an expected value that collides with the
failure value. The probe's positive control is free and already demonstrated:
the pre-fix build must come out NONZERO, and it does, on every target measured
so far.

## What the fix needs

`extern int errno;` cannot become thread-local without the emitter growing TLS
symbols, so this is **Track A object-writer work**, not a lib/crtl edit. Filed
from Track B, where it surfaced.

Related: [[meta-a-pxx-produces-linkable-code]] is the standing umbrella for
object/link/export work and already records a DIFFERENT errno fix (two objects
each reading their own errno, fixed in 243137302 by relocating an exported
definition against its own symbol). That one made two objects share one errno;
this one is that shared errno not being per-thread. They are not the same bug
and the first does not imply the second.

## Bound it puts on other work

**This was written as a prediction and rung 3 has since measured it, so it is
recorded as a measurement.** [[feature-b-a-bootable-image-with-the-busybox-userland-on-it]]
is DONE (2026-09-04) and its image does carry a dynamic busybox: `ldd` on the
258-applet binary names `libc.so.6` and `ld-linux-x86-64.so.2`, and the
initramfs carries both. `gcc -static` on the same objects still refuses with
the TLS/non-TLS `errno` mismatch, so the bound held exactly as stated — it did
not merely go untested. Anything wanting a single-file static pxx userland
waits on this ticket. The same bound applies to frankD's i386
axis. The kiosk finding *"pascal26 and everything it emits are statically
linked"* is true of pxx's own ELF writer output and does NOT extend to anything
the separate-compilation path produces, because that path ends in
`gcc -o out obj/*.o`, which links dynamically by default.

## 2026-09-06 (frankA) — a third independent reading, and a CONSTRAINT that changes "What the fix needs"

### Reproduced, separately written probe

At `1b903c1dd`, compiler `26b8b0adf442`, `--threadsafe`, 200000 iterations each:

    A saw a foreign errno 33 times
    B saw a foreign errno  4 times
    gcc/glibc oracle:      0 and 0

Third reading, third probe, third session (franks-ab, frankD, frankA). Still
live at HEAD.

### THE FIX SHAPE STATED ABOVE IS NECESSARY AND NOT SUFFICIENT

*"Fix needs TLS symbol emission in the object writer"* — measured, and there is
a step in front of it: **pxx programs run with FS base ZERO, in every thread.**

    arch_prctl(ARCH_GET_FS, &v)     rc    value
    gcc/glibc, main thread           0    7a45fdb9c740
    gcc/glibc, pthread child         0    7a45fd7ff6c0     <- distinct
    pxx --threadsafe, main thread    0    0
    pxx --threadsafe, pthread child  0    0                <- same, and zero

Positive control on the instrument, because "the FS base is 0" and "arch_prctl
did not run" print the same 0: the output variable is preloaded with
`0xdeadbeef` and the syscall's return value is read. `rc=0`, sentinel
overwritten — it ran, and it reports zero.

**Emitting `errno` as a TLS symbol into a process with no FS base does not give
it one copy per thread.** Every fs-relative access either faults or resolves to
the same address in every thread — the bug as it stands, with a `.tbss` section
to make it look repaired. The per-thread TCB has to come first, in the thread
PAL's child entry and at startup for the main thread, per target.

### And a cheaper path for THIS ticket specifically

`errno` does not need ELF TLS. glibc's own header is
`#define errno (*__errno_location())`, and the same shape fits here:
`lib/crtl/include/errno.h`'s `extern int errno;` becomes that macro, and the
definition at `lib/crtl/src/stdio.c:66` becomes a per-thread slot.
`lib/crtl/src/pthread.c` already keeps a 64-slot registry keyed by tid.

**The unresolved part is how to find the slot without TLS**, and it has a real
cost either way: `__pxx_pthread_self` is a PAL symbol a non-`--threadsafe` build
does not link, and `gettid(2)` per access puts a syscall on every error path.
Written down rather than chosen, because the choice is a cost trade-off and not
a correctness one.

That path would close the measured race here and would NOT close
[[bug-c-__thread-is-accepted-and-silently-ignored-so-thread-local-storage-is-shared]],
which is the general form: `_Thread_local` and `__thread` are in
`cparser.inc`'s tolerate-by-skipping set, so `__thread int tv = 7;` compiles,
runs, prints 7, and emits an ordinary `.bss` object. This ticket is one instance
of a mechanism that does not exist. Worth knowing which one a fix closes before
starting it.

### Not taken

Diagnosed and parked rather than microfixed. The acceptance above already asks
for a row per target, the fix has a live cost fork, and the general form has
just been filed beside it — none of that is work to start at the end of an
evening. The measurements are banked so the next session does not repeat them.

## 2026-09-07 — the root is SHARED, not ZERO, and the difference decides the fix's control

Reproduced a fourth time, separately written probe, x86-64 `--threadsafe`,
compiler `014583e713be`: **thread A saw not-ENOENT 6 times, thread B saw
not-EBADF 6 times; gcc/glibc 0 and 0.** Nothing below revises the defect.

**What is revised is this ticket's stated root.** The summary says pxx programs
run with *"FS BASE ZERO in every thread"*. That is true in one configuration
and false in another, and both are broken:

| build | main | thread |
| --- | --- | --- |
| gcc / glibc (oracle) | `0x712910136740` | `0x71290fdff6c0` — **distinct** |
| pxx `--threadsafe`, raw-syscall probe, no libc import | `0` | `0` |
| pxx `--threadsafe`, probe importing `arch_prctl` from system libc | `0x7616493e3740` | `0x7616493e3740` — **non-zero and shared** |

Sentinel-controlled in every row: the output variable is pre-set to
`0xDEADBEEFCAFEBABE`, so a syscall that fails and writes nothing cannot be read
as "the base is zero" — the failure and the finding would otherwise be the same
observation.

The third row is the one that matters. Importing anything from the system C
library brings in `ld.so`, which installs a TCB **for the main thread**; pxx's
own clone stub installs none, so the child simply INHERITS the parent's base.
Non-zero, and every thread still resolves an fs-relative access to one place.

**So the invariant is "all threads share one FS base", and "zero" is a symptom
of one link configuration.** This is load-bearing for whoever takes the fix:
a control phrased as *"the FS base is no longer zero"* PASSES on the row above
while the defect is fully present. Assert DISTINCT PER THREAD — a relation,
like this ticket's own errno probe — never non-zero.

## The mechanism, named

`lib/rtl/palthread.pas:87` — `PXX_CLONE_THREAD = $350F00`. Decoded exhaustively,
with the residue checked to zero so nothing is unaccounted:

```
set    CLONE_VM 0x100  CLONE_FS 0x200  CLONE_FILES 0x400  CLONE_SIGHAND 0x800
       CLONE_THREAD 0x10000  CLONE_SYSVSEM 0x40000
       CLONE_PARENT_SETTID 0x100000  CLONE_CHILD_CLEARTID 0x200000
CLEAR  CLONE_SETTLS 0x80000
       accounted 0x350F00, residue 0x000000
```

**`CLONE_SETTLS` is not set, and there is nowhere to put its argument**:
`AN_CLONE` is `__pxxclone(flags, childStack, entry, arg, ctidptr)` (defs.inc:1122)
— five parameters, no `tls`. So this is not a missing flag, it is a missing
parameter on a compiler intrinsic. Anyone costing the "real TLS" path should
cost that, not a constant.

`PalThreadSelf` is `__pxxrawsyscall(SYS_gettid, ...)` (palthread.pas:142), which
is why this ticket's cheaper path records "gettid per access puts a syscall on
every error path" — that is measured now, not assumed: it is the only route to
a thread identity that exists today.

Third route, not costed here and not currently in the ticket: thread stacks are
mmap'd by `PalThreadCreate`, so a size-aligned allocation would let a thread
find its own block by masking `%rsp`, with no syscall and no TLS at all. The
main thread does not have an mmap'd stack and would need its own case. Recorded
so the option is on the table for
[[decide-a-a-foreign-thread-needs-its-own-tls-block-and-the-bounds-are-the-hard-part]]
rather than rediscovered.

## 2026-09-07, second correction — THE PER-THREAD BLOCK ALREADY EXISTS. It is GS, and every reading so far measured FS.

This ticket says *"A per-thread TCB has to come first."* On x86-64 under
`--threadsafe`, **it is already there.** Measured, five threads, relation
asserted (every block differs from every other) rather than any constant:

```
  main   gs=0x45acb8          <- BSS_TLS_MAIN, the static block
  thread gs=0x7b1f496c3a80    <- carved off the top of its own mmap'd stack
  thread gs=0x7b1f495c2a80
  thread gs=0x7b1f494c1a80
  thread gs=0x7b1f493c0a80
  ALL FIVE DISTINCT
```

The same probe reports `fs=0` in every one of them, and glibc is the mirror
image — `fs` distinct per thread, `gs=0`. **pxx's TLS is GS-relative and the
x86-64 psABI is FS-relative** ([[decide-pxx-thread-local-storage-is-gs-relative-and-the-x86-64-psabi-is-fs-relative]]),
so a probe that reads FS is correct about a register pxx does not use. Every
FS reading in this ticket, mine included, is an instrument answering accurately
about something else.

**So the defect is not missing thread-local storage. It is that `errno` never
went into the storage that exists.** `lib/crtl/include/errno.h:5` is
`extern int errno;` — an ordinary `.bss` object — while `compiler/defs.inc`
carries a slot map (`TLS_SLOT_SELF`, `_TID`, `_STACK_LO/_HI`, `_SIG_*`,
`_EXC_*`, `_HEAP_MAGBUSY`) with `TLS_SLOT_FIRST_FREE = 13` and the magazine's
tail starting at 16 — **three free slots**, and `errno` needs one.
`__pxxTlsBase` (AN_TLSBASE, `pasparser_expr.inc:4023`) already returns the
calling thread's block and runs inside parallel workers today.

### What this changes about the fix, and the part that is still hard

- **The cheap path is cheaper than recorded.** No `CLONE_SETTLS`, no new
  `AN_CLONE` parameter, no `gettid` on the error path, no ELF `.tbss`. A slot,
  an `__errno_location()` that adds its offset to `__pxxTlsBase`, and
  `#define errno (*__errno_location())` in the header — which is glibc's own
  spelling.
- **THE REAL CONSTRAINT IS THE TARGET SET, and it was never the TCB.**
  `__pxxTlsBase` refuses on everything but x86-64 (`ir_codegen.inc:217`): the
  other threaded targets have a READABLE thread register (aarch64 `tpidr_el0`,
  arm32 `tpidruro`) and no way to SET one yet. `--threadsafe` covers x86-64,
  i386, aarch64 and arm32, and **this ticket's own table has i386 racing 21/26**.
  So a TLS-slot errno fixes one of four threaded targets and must say so.
- **It does not fix a FOREIGN thread on any target.** A thread created by libc
  `pthread_create` rather than `__pxxclone` never runs the clone stub that
  carves the block, so it inherits its creator's `gs` — measured at
  `ir_codegen.inc:268`, five threads all reading `BSS_TLS_MAIN`. That is
  [[bug-a-a-foreign-thread-shares-the-main-thread-s-heap-magazine]] and errno
  would land in exactly the same hole.

A slot count in prose is a census with an owner elsewhere: re-read
`TLS_SLOT_FIRST_FREE` from defs.inc before taking one. It was 12 when the
comment above it was written.

## 2026-09-07 — THE GROUP, MEASURED INDEPENDENTLY (frank-subcoord). One cause, four symptoms, and the existing test cannot see it

Taken as the entry point to a group rather than alone. **Three open A tickets
state one root cause in their own words** — and three summaries agreeing is not
three measurements, so I reproduced it rather than citing them.

### The measurement, two-armed so it cannot be silently broken

`--threadsafe`, compiler `19bee89a03e635cf`. Arm P is the positive control in
the same binary on the same run: if BOTH arms had come back identical, the
honest reading is a broken probe, not a universal defect.

```
main              4369368
pxx    thread 0   128824687176320     arm P: PalThreadCreate (runs the clone stub)
pxx    thread 1   128824683494016
pxx    thread 2   128824682441344
pxx    thread 3   128824681388672
foreign thread 0  4369368             arm F: libc pthread_create
foreign thread 1  4369368
foreign thread 2  4369368
foreign thread 3  4369368

arm P (control, MUST be 0): colliding pairs = 0
arm F (subject)           : colliding pairs = 6
arm F equal to MAIN base  : 4 of 4
```

**A thread libc created reads the MAIN thread's block.** Every `gs:` slot it
touches is the creator's.

**THE ASSERTION IS DISTINCTNESS, NEVER NON-ZERO.** A foreign thread INHERITS a
valid base, so the failing value is non-zero and dereferences fine — the
expected value collides with the failure value, and this ticket already records
a fix whose "no longer zero" control passed while it was still broken.

### The existing test passes while this is live, and that is a wrong-population control

`test/test_tls_base.pas` exists to assert "blocks genuinely distinct per thread"
and covers three phases — **0** main, **A** clone-stub, **B** manual arch_prctl.
Neither it nor `test_glibc_tls_coexist.pas` contains `pthread_create`. **Every
thread it tests is one pxx created**, which is exactly the population that
works. The control is drawn from the wrong population, so it cannot fail for the
case DOSBox, SDL and every threaded C library produce.

### A FOURTH symptom, not yet ticketed: the signal slots

`bug-a-the-parked-signal-slots-are-process-wide-and-race-across-threads` was
fixed by moving `TLS_SLOT_SIG_CODE/_ADDR/_CTX/_NUM` into the per-thread block
(75875 wrong answers in 400000 deliveries -> 0). `defs.inc:900` explains why
those four are deliberately NOT bounds-validated: a `SA_ONSTACK` handler runs
with rsp on the sigaltstack, so a bounds check would answer "not my block" on
every delivery — and the justification given is *"the writer and the reader here
are the same thread with the same base, so they always agree"*.

**That premise is false for a foreign thread**, by the same argument this
ticket's siblings make: it holds the creator's base. `StatusSlotTlsIndex`
(`exception_emit.inc:24`) maps both the SIG and the EXC families to `gs:` slots
and its own comment says *"Decided entirely at EMISSION. No runtime branch
exists anywhere downstream."* So two libc threads taking signals share all four
slots and the race that fix removed is live again for them.

**Labelled honestly: the two premises are measured (bases shared, above; no
runtime ownership branch, read at `exception_emit.inc:24-42`), the RACE itself
is not.** It needs the original ticket's probe re-pointed at libc threads.

### What the group actually costs, which reorders the fix

The ownership test that would catch all of this **already exists and is
inheritance-proof**: compare the reader's own `rsp` against `TLS_SLOT_STACK_LO/
_HI`, because a block copies byte-for-byte across clone but a stack cannot
(`defs.inc:858-877`). It is emitted at two sites (`ir_codegen.inc:1248`, `:3460`)
and **both are tid sites whose fallback is a `gettid` syscall — they RECOMPUTE a
value.**

`errno` and `EXC_TOP` cannot do that: they need per-thread **storage**, not a
recomputable value. And `EXC_TOP` is touched on every `try` entry and exit,
where the emitter's own comment records refusing even a single `mov rax, gs:[0]`
on cost grounds — so a four-instruction bounds check per access is not available
there either.

**So the three consumers sort into three different fixes, and "apply the
existing check everywhere" is not one of them:**

| consumer | needs | status |
| --- | --- | --- |
| I/O lock, owner tid | a recomputable VALUE | done — bounds check, gettid fallback |
| heap magazine | mutual exclusion only | done — `ba2682d2f` made a shared magazine correct |
| errno, EXC_*, SIG_* | per-thread STORAGE | **open — this is the real design question** |

That last row is the group. Giving a foreign thread a real block pays once at
thread entry instead of per access, which is the only option the hot path
tolerates — and the heap ticket already called it *"the better answer ... a
design question, not a bug fix."*

Probe kept at `scratchpad/tls/probe_foreign_tls.pas`; it is a FAILING test today
so it cannot land in `test/` as a green gate, and it is the natural phase C of
`test_tls_base.pas` once the storage question is settled.

## PARKED 2026-09-07 (frank-subcoord) — free to take, nothing half-done

Fleet dropped to two working seats and this one is idling. **Nothing is
in-flight and nothing is half-edited**: the group finding above is measured,
recorded and pushed, and no code change was started.

**Resume condition: none.** This is not blocked on anything — it is unstaffed.
The next seat can start from the table at the end of the section above; the open
question is the third row (per-thread STORAGE for `errno`, `EXC_*`, `SIG_*` on
threads pxx did not create), and the two decided rows are recorded so they are
not re-litigated.

The probe that reproduces the root cause is at
`scratchpad/tls/probe_foreign_tls.pas` in this session's scratchpad, which is
reaped after 6h — it is ~90 lines and the section above gives its full design
(two arms, control in the same binary, assert distinctness never non-zero), so
rebuild rather than hunt for it.
