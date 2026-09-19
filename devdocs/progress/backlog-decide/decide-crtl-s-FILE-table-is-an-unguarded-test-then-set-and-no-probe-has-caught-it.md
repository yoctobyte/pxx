---
slug: decide-crtl-s-FILE-table-is-an-unguarded-test-then-set-and-no-probe-has-caught-it
track: U
prio: 40
type: decide
status: backlog
created: 2026-09-19
found-by: frankS
owner: ""
blocked-by: []
summary: "`__crtl_alloc_file` (lib/crtl/src/stdio.c) picks a FILE from a 16-entry table with `if (!files[i].heap) { files[i].heap = 1; return &files[i]; }` — test-then-set, no atomic, no lock, and stdio.c's own comment at line 1181 says outright that crtl's FILE has no lock and the flockfile family is a no-op for single-threaded streams. Two concurrent fopen() calls can therefore be handed the SAME FILE*. MECHANISM CLEAR, RACE NOT OBSERVED: two probes failed to produce it and BOTH failures are recorded below so nobody re-runs them. THE FORK IS NOT TECHNICAL, which is why this is a decide and not a bug: do we want crtl's stdio to be thread-safe at all, or is it a single-threaded runtime whose flockfile no-ops are an honest statement of that? If the first, this is one cmpxchg and the FILE lock stops being a no-op; if the second, the answer is a documented refusal and nobody should spend another probe on it. Measured today: pthread_create IS trampolined and errno IS per-thread, so threaded C on pxx now runs, which is what makes the question live rather than theoretical."
---

# The question, in one sentence with no implementation noun in it

**Do we want a C program with threads to be able to use stdio, or is pxx's C
runtime single-threaded and honest about it?**

Everything else here is engineering and is ours. That sentence is not.

# What is actually in the code

`lib/crtl/src/stdio.c`:

    static FILE __crtl_files[16];

    static FILE *__crtl_alloc_file(void) {
      int i;
      for (i = 0; i < 16; i++) {
        if (!__crtl_files[i].heap) {
          __crtl_files[i].heap = 1;
          return &__crtl_files[i];
        }
      }
      return 0;
    }

Test-then-set with no atomic. Two threads can both read `heap == 0` for the
same slot and both be handed that `FILE *`. The same file says at line 1181
that the `_unlocked` variants differ from the plain ones "only by skipping the
per-FILE lock, and crtl's FILE has no lock", and at 1207 that the lock
operations themselves are no-ops "for single-threaded streams". So this is not
an oversight anyone hid; it is a stated stance, and the stance is what needs
re-deciding now that threaded C runs.

`pxx_popens[16]` in the same file has the same shape.

# Both probes, and why neither is evidence

Recorded so the next reader does not spend the same hour.

**Probe 1** — two threads, 20000 iterations each, `fopen`/`fclose` in a loop,
counting iterations where both held a non-NULL `FILE *` and where those were
equal:

    overlap=6  same-FILE-handed-to-both=0
    overlap=4  same-FILE-handed-to-both=0
    overlap=0  same-FILE-handed-to-both=0   <- reported "PROBE PROVED NOTHING"

Overlap of 4-6 in 20000 is the finding: `fopen`+`fclose` is fast and the
test-then-set window is a handful of instructions, so the threads almost never
occupy the allocator together. The third run overlapped zero times, and the
only reason that zero was not read as a clean bill is that the probe asserted
its own precondition and said so.

**Probe 2** — aimed properly: main holds 15 of the 16 slots so both threads
scan the same taken entries and arrive at slot 15 together, turning the window
into a rendezvous. **It deadlocked in its own spin logic and was killed at 60s.**
That is a fact about the harness, not about the code.

# What the decision changes

**If thread-safe stdio is wanted:** the allocator needs a compare-and-swap on
`heap` (the pattern already exists — `ba2682d2f` made the heap magazine's
ownership guard an `xchg r64, m64` for exactly this class), and `flockfile`
stops being a no-op. An unguarded test-then-set on a shared table arguably
justifies that on the code shape alone, without a demonstrated race.

**If it is not wanted:** say so in `stdio.h`, keep the no-ops, and this closes
as `known-incompat` — a true and reproducible property that is chosen rather
than tolerated. What is NOT acceptable is the current middle, where the code
looks like it might be safe and the comment saying otherwise is 1100 lines
away from the allocator.

# Why it is live now and was not before

Measured 2026-09-19 in the per-thread-state group: `lib/crtl` defines
`pthread_create` itself and routes it through `PxxPthreadStart`, which installs
a real per-thread TLS block; `errno` became `__thread` the same day. Threaded C
on pxx now runs and gets correct per-thread errno. stdio is the next thing such
a program touches.

# Do not re-probe this

If the decision is "make it safe", the cmpxchg is justified by the code shape
and a probe is not required to authorise it. If a demonstration is genuinely
wanted, widen the window INSIDE the allocator (a debug build with a delay
between the test and the set) rather than around it — probe 1 shows that
arranging contention from outside does not reach a window this narrow.
