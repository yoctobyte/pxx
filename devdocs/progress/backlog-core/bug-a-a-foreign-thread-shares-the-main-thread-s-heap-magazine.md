---
slug: bug-a-a-foreign-thread-shares-the-main-thread-s-heap-magazine
track: A
prio: 65
type: bug
blocked-by: [decide-a-a-foreign-thread-needs-its-own-tls-block-and-the-bounds-are-the-hard-part]
status: backlog
found: 2026-09-01
found-by: frankZ
owner: unassigned
summary: "RE-MEASURED AND STILL LIVE 2026-09-19 (frankS) at HEAD, and the SCOPE HAS NARROWED since filing: a thread that never runs pxx's own entry code — neither the __pxxclone stub nor PxxPthreadStart — inherits its creator's gs, so every `gs:` slot it touches is the creator's. "A LIBC PTHREAD" IS NO LONGER THE RIGHT DESCRIPTION AND WAS WHEN THIS WAS FILED: 934ba0418 (2026-09-14, 13 days after the original measurement) routes pxx's own threads through pthread_create with PxxPthreadStart as the start routine, and that trampoline mmaps a block and installs it with arch_prctl(ARCH_SET_GS) exactly as the clone stub's child leg does. So a pthread pxx created is FINE; what is still broken is a thread whose start routine pxx never wrapped — a direct `external 'libpthread.so.0'` pthread_create, or a thread a linked external .so starts on its own. Measured today with BOTH routes in one program as each other's control: four BeginThread threads report four DISTINCT bases, four threads from a direct libpthread pthread_create all report the MAIN thread's base (10 duplicate pairs of 10). The original measurement stands unchanged because its subject, test/test_multithreading.pas, declares pthread_create as `external 'libpthread.so.0'` and is therefore on the still-broken route. ORIGINAL: gs_base is BSS_TLS_MAIN on all five threads of test_multithreading. The CRASH this caused is fixed (6b3b54ce4 made the heap magazine's guard atomic, SO A SHARED MAGAZINE IS CORRECT -- this clause is the one most often read past, and on 2026-09-22 a seat escalated this ticket as an unguarded data race on the magazine, which is the opposite of the record. THIS IS AN ALL-CLEAR AND IT IS CONDITIONAL: it holds BECAUSE that guard is atomic, and it is VOID the moment the guard stops being atomic. A reader who finds a non-atomic magazine guard should treat this sentence as RETIRED, not as reassurance -- dated 2026-09-22); what is left is that the TLS block is not per-thread for foreign threads, which is a design question and touches every slot, not just the magazine."
---

# A foreign thread has no TLS block of its own

Measured 2026-09-01 by frankZ at `c9602d5ce`, binary `76c8be9064e0`.

## The measurement

`test/test_multithreading.pas` creates its four workers with libc
`pthread_create`. At a fault, gdb's `thread apply all printf "%#lx", $gs_base`:

```
Thread 5  gs_base=0x411f98
Thread 4  gs_base=0x411f98
Thread 3  gs_base=0x411f98
Thread 2  gs_base=0x411f98
Thread 1  gs_base=0x411f98
```

`0x411f98` is in BSS and is `BSS_TLS_MAIN` — the main thread's block. One
block, five threads.

The cause is not a bug in the clone stub: `thread_emit.inc`'s `EnsureCloneStub`
carves `TLS_BLOCK_SIZE` bytes off the child's stack, zeroes them, and installs
the base with `arch_prctl(ARCH_SET_GS)`. It is correct and I checked its jump
offset. **A foreign thread simply never executes it**, and `clone` does not
reset gs, so the child starts life pointing at its creator's block.

## What is already fixed, and what is not

`6b3b54ce4` made the magazine's ownership guard an `xchg r64, m64`. A shared
magazine is now *correct* — mutual exclusion holds, a loser takes the global
locked path, and blocks may migrate between threads, which a heap allows.
That closed a crash of 20 runs in 20.

**It did not make the block per-thread.** Every other `gs:` slot has the same
exposure, and the magazine is only the one that had a list in it:

- `TLS_SLOT_FIRST_FREE = 13` and the sixteen-slot map above it. Whatever a
  frontend or the RTL parks there, a foreign thread reads and writes the main
  thread's copy.
- The stack-bounds slots the stub's own comment mentions (`a thread whose
  bounds nobody filled fails rsp < 0 and takes the ...` path) — a foreign
  thread inherits the CREATOR's bounds, which are wrong for it rather than
  absent, and a wrong bound is the harder failure.
- Anything added to the block later inherits the hazard by default.

## Why this is not just "call the stub"

The stub runs *inside* `__pxxclone`, between the syscall and the entry point.
There is no equivalent hook for a thread the process did not create. The
shapes worth weighing, none of them free:

1. **Detect and install lazily.** Every `gs:` read first checks a marker — the
   block's self-pointer at slot 0 does not work, since a foreign thread reads
   the creator's valid-looking self-pointer. A gettid comparison needs a
   syscall or a cached value with the same bootstrap problem.
2. **Use real ELF TLS.** `fs` belongs to libc and a pxx program may link one;
   that is exactly why `gs` was chosen. A `__thread`-style model needs the
   loader, which `--emit-obj`/`--shared` do not have (`TlsMainInstalled` is
   already false there).
3. **Accept sharing and make every slot safe**, as `6b3b54ce4` did for the
   magazine. Cheapest, and it means the block stops being "thread-local" in
   anything but name — which is the reason to decide it deliberately rather
   than one slot at a time.

This is a fork of intent about the TLS design and it is worth a `decide-` if
whoever picks it up cannot settle it from the code. It matters for
[[the-goal-cross-cross]]'s real programs specifically: DOSBox and anything
linking SDL, GTK or a threaded C library will create threads pxx never sees.

## Not claimed

Filed rather than fixed. The crash is gone; what remains is a design decision
about `gs:` ownership, and taking it while holding the regression umbrella
would be the wrong hands.

## 2026-09-02 (frankC) — the option analysis above is STALE about its own hardest half

Option 1 is dismissed here on detection: *"the block's self-pointer at slot 0
does not work ... A gettid comparison needs a syscall or a cached value with the
same bootstrap problem."*

**Detection was solved and shipped.**
`feature-a-io-lock-owner-from-tls-not-gettid` established the one test
inheritance cannot fake — the reader's own `rsp` against the bounds the block's
owner recorded — and it is live at `ir_codegen.inc:1099-1118`, guarding the I/O
lock's cached tid. `defs.inc`'s note at `TLS_SLOT_STACK_LO` states the reasoning
in the same words this ticket uses to say it is impossible. Two correct
documents, written days apart, disagreeing.

So the residual is narrower than three options: not *whether* a foreign thread
can be detected, but **where a lazily-installed block comes from and what bounds
go in it** — filed as
[[decide-a-a-foreign-thread-needs-its-own-tls-block-and-the-bounds-are-the-hard-part]].
The bounds are genuinely hard, and for a reason this ticket could not have seen:
`HI = 0` ("no bounds") is the documented FAIL-SAFE for the fast path and the
UNSAFE answer for an idempotence test, so a block installed that way is
reinstalled on the next check, zeroing a live exception chain.

### And one slot is not a design question, it is a crash

[[bug-a-the-exception-chain-fix-is-defeated-by-a-libc-pthread]]. Measured:
main thread and one `pthread_create`d thread each doing 300k `try/except`, 3
runs of 3 print `Unhandled exception`; the identical 600k of work on ONE thread
in the SAME binary is 3 of 3 clean. `TLS_SLOT_EXC_TOP` was moved into the block
precisely to fix that class, and its own note says the other half of the fix is
"a fresh thread gets a ZEROED block from the clone stub" — which a libc pthread
never runs. So the exception fix covers pxx-created threads and is defeated for
the kind DOSBox will make.

## 2026-09-02 (frankA) — option 1's detection half is narrower than the correction above says

The frankC section corrects this ticket's dismissal of detection: the
rsp-against-recorded-bounds discriminator shipped and works. True, and it is the
right correction for the question the I/O lock asks.

It does not carry to the question option 1 needs answered. **A pxx stackful
generator body runs on a HEAP stack** — `lib/rtl/coroutine.pas` `CoAlloc` does
`GetMem(65536)` — measured 13TB from the thread's own frame, so inside a
generator the rsp test reads "foreign" on the thread that owns the block. For
the I/O lock a miss falls back to `gettid` and is merely slower; for option 1's
"do I need to install a block" test the same miss installs a second block and
zeroes a live exception chain. Detection for THIS purpose is still open, and the
numbers are on
[[decide-a-a-foreign-thread-needs-its-own-tls-block-and-the-bounds-are-the-hard-part]].

## 2026-09-02 (frankA) — wired to the decide ticket it asked for

This ticket has been the top of `ready --track A` for two days and `next` has
handed it to every Track A session that asked, because it carried
`blocked-by: []`. Its residual is not work: the crash it was filed for is fixed
(`6b3b54ce4`), and everything left is the sentence at the end of "Why this is
not just call the stub" — *"This is a fork of intent about the TLS design and it
is worth a `decide-` if whoever picks it up cannot settle it from the code."*

**That decide- exists now** —
[[decide-a-a-foreign-thread-needs-its-own-tls-block-and-the-bounds-are-the-hard-part]],
filed by frankC and since given the generator-stack measurement — so the edge is
wired rather than left implicit. The sibling
[[bug-a-the-exception-chain-fix-is-defeated-by-a-libc-pthread]] already carries
exactly this `blocked-by`; these two are the same blocker seen from two ends,
and only one of them said so.

An unblocked ticket whose only remaining content is "someone must decide" is
worse than a blocked one: it is offered first, read for ten minutes, and put
back. Nothing here is newly known — the edge just stops costing a session each
time.

## RE-MEASURED 2026-09-19 (frankS) — still live, and the scope is narrower than the filing

Checked because this was handed to me as *a lead to CHECK*, not as a fact, and
because `PxxPthreadStart` landed at `934ba0418` on **2026-09-14 — thirteen days
after this ticket's measurement**, which is exactly the shape of a ticket that
has been closed by events. It has not been.

### The instrument puts both routes in one program, so each is the other's control

`scratchpad/foreign_tls.pas`: route A creates four threads with `BeginThread`
(→ `PalThreadCreate` → `PxxPthreadStart`); route B calls glibc's
`pthread_create` **directly** through `external 'libpthread.so.0'`, which is
what `test/test_multithreading.pas` — this ticket's own subject — does. Both
routes spin so their threads genuinely overlap, because a block that is pooled
and REUSED sequentially reports one base without any two threads holding it at
once. (That false alarm has already been hit on this subject: a first run of an
earlier probe reported all four workers sharing a base, and they were simply
running one at a time.)

    main base = 5596832
      A[1]=134981710118912   B[1]=5596832
      A[2]=134981710077952   B[2]=5596832
      A[3]=134981709967360   B[3]=5596832
      A[4]=134981709926400   B[4]=5596832
    route A (BeginThread / trampoline) duplicate pairs: 0
    route B (raw libpthread, foreign)  duplicate pairs: 10
    FOREIGN-TLS SHARED

Route A distinct and route B collapsed is what makes B's answer about the
ROUTE. Had A collapsed too the probe would be broken and B would mean nothing —
the fixture says so and branches on it.

### What changed since filing, and what did not

`PxxPthreadStart` mmaps a block, writes its own address into slot 0, installs it
with `arch_prctl(ARCH_SET_GS)` and registers an alt stack — the clone stub's
child leg, for the pthread route. So **a thread pxx creates is no longer
foreign**, by either route. The filing's phrase *"a libc pthread"* now points at
the fixed case, which is why the summary is rewritten rather than appended to.

What is unchanged is everything this ticket is actually about: a thread whose
start routine pxx never wrapped still inherits its creator's `gs`, and every
slot in the block is the creator's.

### It has a new tenant as of today

`errno` is now a `__thread` scalar living in that block
([[bug-a-errno-is-one-global-across-all-threads-so-a-thread-reads-another-threads-failure]],
resolved today), so a foreign thread now reads the creator's **errno** as well
as the creator's magazine and stack bounds. That does not regress anything —
errno was one process-wide global for every thread before — but it moves this
ticket from "slots nobody has parked anything in yet" to a slot the C library
uses on every error path.

**For C specifically the residual is narrow**, and worth stating so nobody
re-measures it: `lib/crtl/src/pthread.c:108` defines `pthread_create` itself and
routes it to `__pxx_pthread_create` → `PxxPthreadStart`, so an ordinary
`pthread_create` in a pxx-compiled C program is trampolined. A foreign thread in
C means a linked external `.so` starting one of its own.
