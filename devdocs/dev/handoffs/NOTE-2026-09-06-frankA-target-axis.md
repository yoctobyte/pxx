# Note to self — frankA, 2026-09-06 evening

Written at the owner's request, because the pin-and-release turn interrupted
mid-thought. **This is state, not instructions.** Nothing here is a rule and
CLAUDE.md outranks all of it. The test I wrote it against: could a fresh session
with none of my context pick this up?

Session: `https://claude.ai/code/session_017JQMYrELfziEkCq3rod2Ny`. Everything
below is pushed unless a line says otherwise.

## What I am about to do, and why that rather than the alternative

**Taking the target axis**, under the owner's "fix all cross-, frontend- and
target- issues" scope. Two things in order:

1. **My own two `--byte-prefix` i386 tickets** (`d0e8aeedb`, filed 2026-09-03):
   `bug-a-i386-copy-and-pos-segfault-under-the-byte-prefix-mode` (p80) and
   `bug-a-i386-refuses-a-frozen-record-field-write-under-the-byte-prefix-mode`
   (p75). First because they are already diagnosed, they are mine, and they are
   exactly the native-invisible class the release bar cares about — a 20-probe
   suite matched 18/20 on x86-64 while i386 had three failures.
2. **Then a sweep for the native-only class** — hard-coded byte counts, widths,
   alignments, pointer sizes in `compiler/**` and `lib/**`.

**Not** the errno/`__thread` fix. See the parked judgement below.

**On the sweep, the thing I had decided and would otherwise re-derive:** assert
RELATIONS, never per-target constants — `SizeOf(P) = 2 * SizeOf(Pointer)`, not
`SizeOf(P) = 16`. A relation carries no expected width, passes on every target,
and prints a different correct number on each. A constant row has to be written
per target and the one nobody runs is the one that rots. This is CLAUDE.md's own
guidance and it is the shape that survives the release.

## Measurements I took that are in files, so nobody re-runs them

All in the tickets already; listed so a fresh session knows they exist.

- **FS base is ZERO in every pxx thread.** `arch_prctl(ARCH_GET_FS)` rc=0
  value=0 in the main thread AND a `pthread_create`d one; glibc gives distinct
  non-zero. Instrument positive-controlled: output preloaded with `0xdeadbeef`
  and the syscall's rc read, because "the base is 0" and "the syscall did not
  run" both print 0. **This is the reading that invalidates the errno ticket's
  stated fix shape.**
- **No `.tbss`/`.tdata` in any pxx object**; `__thread` becomes a plain `.bss`
  `OBJECT`. Confirmed independently by frankC afterwards.
- **errno race reproduced at `1b903c1dd`**: 33 and 4 foreign values per 200000
  iterations, oracle 0 and 0. Third reading, third probe, third session.
- **i386 relocation flap**: old compiler 1/0/1 across an unrelated extra local
  in `PXXIoCheck`, new compiler 0/0/0.
- **xtensa link**: 25 undefined refs from the pin and from HEAD, both ABIs;
  riscv32 0. Moved into frankZ's ticket.

## What I ruled out, so nobody re-runs THAT

- **Announcing every PREFIX** as the i386 guard fix. Sound only with total
  coverage — 117 prefix bytes in `ir_codegen386.inc`, 1579 `EmitB` sites, no
  choke point — and a missed site flips the guard to ACCEPT, which is a silent
  wrong-width access. Rejected in favour of recording where the instruction
  BEGAN, whose absence is conservative. **Do not revisit the prefix version.**
- **Narrowing the prefix byte set** (e.g. "LOCK cannot precede A3"): true and
  useless, because `$66` is both a legal prefix and an ordinary displacement
  byte. The ambiguity survives any narrowing.
- **Refusing `__thread`** instead of warning. Measured population under `test/`,
  `lib/`, `examples/` is ZERO, so refusing is free HERE — which is why the empty
  population is not the argument. It would stop single-threaded programs that
  merely mention `__thread`, and those are correct today, so it breaks working
  programs to protect broken ones. Landed a warning instead.
- **`git checkout -- <file>`** as a control restore. Use
  `git checkout HEAD -- <file>`; the plain form restores from the INDEX.

## The parked judgement, which is the part that does not survive on its own

**The errno fix is parked and the REASON is a judgement, not a blocker.**
frankuser asked, I declined, they backed it, the owner's freeze then made it
moot. Recording it so nobody reads the park as "blocked":

- The ticket's stated fix (TLS symbols in the object writer) **cannot work
  alone** — FS base zero. The per-thread TCB comes first, per target.
- A cheaper path closes the errno race without ELF TLS: glibc's own header shape
  `#define errno (*__errno_location())` over `lib/crtl/src/pthread.c`'s existing
  64-slot tid-keyed registry, replacing `int errno;` at `lib/crtl/src/stdio.c:66`.
- **Its open question is a COST fork, not a correctness one, and it is
  unresolved:** `__pxx_pthread_self` is a PAL symbol a non-`--threadsafe` build
  does not link, and `gettid(2)` per access puts a syscall on every error path.
  Neither is obviously right. **This is the premise I was relying on and have
  not checked: I did not measure the cost of either option.**
- It closes the errno ticket and NOT
  `bug-c-__thread-is-accepted-and-silently-ignored-so-thread-local-storage-is-shared`,
  which is the general form.
- Why parked: a libc-level change to the most-read variable in C, with a live
  cost fork, at the end of an evening, hours before a release. Any two of those
  would have been enough.

## Unchecked premises elsewhere

- **The ratchet's 20** in `test-emit-obj` is today's measurement on THIS box's
  toolchain. I did not check it is stable across ESP-IDF versions.
- **`EmitMovGlobAcc` adoption is partial by design.** Only the moffs family
  (A0–A3) announces `X386InstrStart`. Every other rewritable shape still
  refuses, so more absolute relocations may exist that nothing currently
  measures. The design makes that safe, not absent.
- **`X386InstrStart` relies on code offsets being MONOTONE.** I found and
  cleared one `CodeLen` rewind (`cparser.inc`'s thunk). I did not prove there is
  no other path that rewinds it.

## Things I hold that are finished

Nothing is half-landed. The N-D partial-index fixture is IN (`8c57bf274`) —
frankC's message suggesting it is still a judgement call predates that push.
