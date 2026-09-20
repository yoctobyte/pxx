---
slug: decide-should-a-python-program-that-imports-threading-compile-as-written
title: should a Python program that imports threading compile as written?
summary: >
  ONE QUESTION, and the cost behind it is now measured so the answer is not a
  guess: today `import threading` is a hard compile refusal unless the person
  passes --threadsafe on the command line, and lekkerzeilen is refused by it.
  Making it automatic is easy. The reason nobody has is a STANCE, not a
  difficulty -- threads are opt-in because pxx answers concurrency with
  coroutines, and a locked heap is a bad trade for concurrency you could have
  had cooperatively. That stance was stated before anyone had measured what
  the locks cost. They cost +0.4% on a real application phase, +26% on pure
  string churn, +0.9% on image size, and nothing on I/O. The question is
  whether that changes the stance.
track: U
type: decide
prio: 55
owner:
status: open
---

# The question

> **Do we want a Python program that imports `threading` to compile as it is
> written — or do we want threads to stay something you ask for explicitly?**

Nothing else in this ticket is a question for you. If the answer is "as
written", the mechanism is ours and we will pick it.

# Why it is being asked now

`lekkerzeilen` imports `threading` in `app.py` and `gauges.py`, so the
unmodified tree does not compile: it needs `--threadsafe` typed on the command
line, or it stops with an error. Every seat working on it has been passing that
flag by hand. It is a demo we want to be able to hand to someone.

CPython needs no such flag, so this is the one direction NilPy is not supposed
to diverge in: refusing source that CPython runs.

# Why it was not already done — your own reasoning, 2026-08-10

> *"we spend a lot of work making async and coroutines work, even with pascal.
> and for exactly this reason. cause threads are nice, if you have multiple
> CPU's. they suck on single core - where timeslicing pwns the game"*

So threads being opt-in is the language saying: the common concurrency case
does not need threads and should not pay for them. **That is the thing this
ticket asks you to confirm or revise**, and it is why it is not an engineering
call. Paying is what the stance is about, so here is what paying costs.

# What the locks actually cost — measured 2026-09-20, compiler 6b3f65304a6e

Same source, same compiler, two binaries, run interleaved, min-of-5 inside the
program and best of three runs:

| workload | threads off | threads on | delta |
| --- | --- | --- | --- |
| lekkerzeilen chart build (a real app phase) | 3.384 s | 3.396 s | +0.4% |
| list/alloc churn, 200k iterations | 0.285 s | 0.291 s | +2% |
| string + refcount churn, 200k iterations | 0.043 s | 0.054 s | +26% |
| console output, 100k lines | 0.511 s | 0.511 s | 0% |
| `print("hello")` binary | 1,458,348 B | 1,470,908 B | +0.9% |

For scale, CPython runs that string micro in 0.031 s, so our locked build is
1.7x CPython there and our unlocked build is 1.4x.

**The cost is real, small, and concentrated in reference-count traffic.** It is
not spread evenly: a program that shuffles strings pays 26%, and an application
doing actual work pays half a percent.

# The three ways to say "as written", if that is the answer

Stated plainly, because the choice between them is ours and not yours:

1. **Look at the program's imports before compiling it.** Only programs that
   import threading pay. When the look-ahead cannot follow an import it misses
   it, and the person gets exactly today's error — never anything worse. It can
   also guess wrong the other way, turning locks on for a program whose
   `import threading` sits in a branch that never runs.
2. **Any `.py` file in the directory mentioning threading turns it on.** Cannot
   miss; makes compilation depend on files the program does not import, which
   is hard to explain when it surprises someone.
3. **Every Python program gets threads.** No look-ahead, never wrong, and it is
   the one that contradicts the stance above: it makes the cost in that table
   universal rather than confined to programs that asked.

Your own fourth idea — start compiling, discover threads, throw it away and
start again — was waived on 2026-08-10 and is measured now: the wasted work is
only the part before the discovery, 18.5 s of lekkerzeilen's 122 s compile, so
about +15%, not double. It is not free to build, though: the compiler
deliberately has no `execve`, so restarting means resetting its own state in
place.

# What the demo actually uses -- measured 2026-09-20, not surveyed

lekkerzeilen-7a supplied the list and I ran it, compiler `f17bf2485348`, so
the surface this question is really about is small and fully supported:

| name | sites | works? |
| --- | --- | --- |
| `threading.Thread(target=, args=, daemon=True, name=)` | 4 (app.py 842, 1258, 2527; gauges.py 435) | yes |
| `.start()` / `.join(timeout=2.0)` | app.py 1163, 1198, 4293 | yes |
| `threading.Event()` + `.set()` / `.is_set()` / `.wait(t)` | 1 (gauges.py 402) | yes |

Nothing else: no Lock, RLock, Condition, Semaphore, Timer, `current_thread`,
`local` or Barrier. Every `Thread` is `daemon=True`, which
`lib/rtl/mimic_threading.pas` records as the FREE arm -- a non-daemon thread is
the one that costs, and the app has none. One `target` is a BOUND METHOD, which
reaches the thread entry through a different door than a plain function;
checked on purpose, works.

Oracle RUN rather than asserted: CPython 3.14.4 on the same file prints
byte-identical output.

**So nothing is missing.** There is no feature gap behind this question and no
workaround anyone is carrying -- the ONLY thing between the unmodified tree and
a compile is the `--threadsafe` flag, which makes this purely the stance
question above and not a capability one.

**Not the RTLEvent ticket, despite the name.**
`feature-b-the-rtlevent-family-is-absent-from-the-threading-rtl` (backlog-libs,
p35) is about FPC's Pascal `PRTLEvent`/`RTLEventCreate`/`RTLeventWaitFor`
spelling, which nothing in the app touches. `threading.Event` is a separate
class backed by palsync's futex-backed `TEvent`. The two were conflated on the
strength of the word "Event"; they share no code.

# Recommendation

**Answer "as written", and we implement option 1.** It keeps your stance
intact — a program that never mentions threads never pays anything — while the
demo compiles the way a Python programmer wrote it. The 26% row is the honest
worst case and it lands only on programs that asked for threads.

If you would rather keep threads explicit, say so and this ticket closes: the
diagnostic already names the flag, and as of `974db9eb9` it no longer names it
on targets where the flag does not exist.
