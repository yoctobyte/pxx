---
track: C
prio: 60
type: bug
status: backlog
owner: ""
created: 2026-09-06
found-by: frankA
tags: [tls, threads, c-frontend, errno]
blocked-by: []
summary: "`__thread` and `_Thread_local` are in cparser.inc's CIsTopLevelSkipIdent -- the tolerate-by-skipping set -- so `__thread int tv = 7;` COMPILES, RUNS, prints 7, and emits an ordinary GLOBAL OBJECT in .bss. There is no .tbss or .tdata section in any pxx object. Every thread therefore shares one copy of a variable the programmer declared per-thread, with no diagnostic anywhere. This is the GENERAL form of [[bug-a-errno-is-one-global-across-all-threads-so-a-thread-reads-another-threads-failure]]: errno is one instance of a mechanism that does not exist. AND THE TWO FRONTENDS DISAGREE ABOUT THE SAME MISSING FEATURE -- Pascal REFUSES `threadvar` loudly (`expected 'begin' before 'threadvar'`), which is the honest failure; C accepts and ignores it, and C is where errno lives. Measured 2026-09-06 at 1b903c1dd. A SECOND MEASUREMENT BOUNDS ANY FIX: pxx programs run with FS BASE ZERO in every thread -- arch_prctl(ARCH_GET_FS) returns rc=0 and value 0 in both the main thread and a pthread_create'd one, against distinct non-zero values under glibc -- so emitting TLS symbols alone cannot work, because every fs-relative access in every thread would resolve to the same place. Whatever fixes this has to set a per-thread FS base (or the per-target equivalent) BEFORE the object writer's TLS support is worth anything."
---

# `__thread` is accepted and silently ignored

## Measured, 2026-09-06, at `1b903c1dd` / compiler `26b8b0adf442`

    __thread int tv = 7;
    int main(void){ printf("%d\n", tv); return 0; }

compiles clean, runs, prints `7`. The object:

    865: ... 4 OBJECT WEAK   DEFAULT 5 errno
    866: ... 4 OBJECT GLOBAL DEFAULT 5 tv        <- section 5 is .bss

`readelf -SW` finds **no `.tbss` and no `.tdata`** in any pxx object. The
storage class is dropped: `cparser.inc:11904` lists `_Thread_local` and
`__thread` in `CIsTopLevelSkipIdent`, whose own comment describes the set as
*"storage-class and function specifiers pxx does not model as type tokens but
tolerates by skipping"*.

Tolerating by skipping is right for `register` and `__restrict`, which are
hints. It is wrong for `__thread`, which changes what the program MEANS. Under
*"on par with the language, not with FPC"* this is squarely a bug and not a
compat item: a programmer writing `__thread` meant one copy per thread, that is
what the source says, and we give them one copy shared.

## The two frontends disagree about the same missing feature

| frontend | spelling | what happens |
| --- | --- | --- |
| Pascal | `threadvar tv: Integer;` | **refused**: `expected 'begin' before 'threadvar'` |
| C | `__thread int tv;` | **accepted, ignored** |

The Pascal refusal is the honest failure — it stops, and nobody ships a program
believing it has per-thread state. The C side is the silent one, and C is where
`errno` lives. Same absent mechanism, opposite failure modes, and the dangerous
one is in the frontend that needs it most.

## Why this is the general form of the errno bug

[[bug-a-errno-is-one-global-across-all-threads-so-a-thread-reads-another-threads-failure]]
reports `errno` shared across threads and names its root as
`lib/crtl/include/errno.h:5`'s `extern int errno;`. That is accurate, but it is
one *instance*: C11 7.5 requires `errno` to be thread-local, and pxx has no
thread-local anything. Fixing `errno` alone leaves every other `__thread`
declaration silently shared.

Reproduced the errno race independently while measuring this, at `1b903c1dd`
with a separately written probe: **A saw a foreign errno 33 times, B 4 times,
over 200000 iterations each; gcc/glibc 0 and 0.** That is the third independent
reading (franks-ab, frankD, and this one), each with its own probe.

## THE CONSTRAINT THAT BOUNDS ANY FIX — measured, not assumed

**pxx programs run with FS base ZERO, in every thread.**

    arch_prctl(ARCH_GET_FS, &v)     rc    value
    gcc/glibc, main thread           0    7a45fdb9c740
    gcc/glibc, pthread child         0    7a45fd7ff6c0     <- distinct
    pxx --threadsafe, main thread    0    0
    pxx --threadsafe, pthread child  0    0                <- same, and zero

Positive control on the instrument itself: the output variable is preloaded with
`0xdeadbeef` and the syscall's return value is read, so "the FS base is 0" and
"arch_prctl did not run" are distinguishable. `rc=0` and the sentinel overwritten
— the syscall ran and reports zero.

**So the errno ticket's stated fix — "grow TLS symbols in the object writer" —
is necessary and not sufficient, and on its own it would be worse than nothing:**
fs-relative accesses in a process with no FS base either fault or resolve every
thread to the same address, which is the bug it was meant to fix, now with an
ELF section to make it look fixed. Ordering matters:

1. a per-thread TCB with a distinct FS base, set in the thread PAL's child
   entry (x86-64 `arch_prctl(ARCH_SET_FS)`; the per-target equivalent
   elsewhere), **and** for the main thread at startup;
2. `.tbss`/`.tdata` and the TLS relocations in the object writer, per backend;
3. `__thread` stops being skipped in `cparser.inc`.

## A cheaper path exists for errno alone, and it is worth pricing before (1)-(3)

`errno` does not need ELF TLS. glibc itself does not use a bare TLS object for
it in the ABI sense — the header is `#define errno (*__errno_location())`, and
the same shape works here:

- `lib/crtl/include/errno.h` declares `int *__errno_location(void)` and defines
  the macro, instead of `extern int errno;`
- the definition (today `int errno;` at `lib/crtl/src/stdio.c:66`) becomes a
  per-thread slot

**The open question is how a slot is found without TLS, and it has a real cost.**
`lib/crtl/src/pthread.c` already keeps a 64-slot registry keyed by tid
(`pxx_thr_reg`), so a lookup exists — but `__pxx_pthread_self` is a PAL symbol
that a non-`--threadsafe` build does not link, and `gettid(2)` on every errno
access puts a syscall on every error path. Neither is obviously right, which is
why this is written down rather than chosen here.

**It also does not fix `__thread`,** so it is a repair for the ticket next door
and not for this one. Worth doing first if the errno race is the urgent part;
worth knowing it does not close this.

## Acceptance

**Assert the RELATION, never a per-target constant** — two threads writing and
reading the same `__thread` variable must never see each other's value — so the
row needs no expected value and cannot pass by agreeing with a default.

**A row per target with an object writer.** TLS is emitted per backend and the
FS-base equivalent differs per architecture, so one green on x86-64 closes
nothing. The pre-fix build must come out WRONG on each, and it does today: the
variable is one `.bss` object everywhere.

**And assert the FS base is distinct per thread**, separately from the variable
test. The two can fail independently, and a probe that only reads the variable
cannot tell "TLS is not emitted" from "TLS is emitted and every thread resolves
it to the same block".
