---
slug: decide-a-a-foreign-thread-needs-its-own-tls-block-and-the-bounds-are-the-hard-part
track: U
prio: 70
type: decide
status: backlog
created: 2026-09-02
found-by: frankC
owner: ""
blocked-by: []
summary: "DETECTING a foreign thread is SOLVED and shipped -- the rsp-against-recorded-bounds test from feature-a-io-lock-owner-from-tls-not-gettid, live in ir_codegen.inc. What is undecided is where a lazily-installed block COMES FROM and what stack bounds go in it, and the two interact: install with bounds unset (HI=0, the documented fail-safe) and everything is correct but the NEXT check reads the thread as foreign again and reinstalls, zeroing a live exception chain mid-flight. Guessed bounds avoid that and a wrong bound is the harder failure. This blocks a program that fails today: bug-a-the-exception-chain-fix-is-defeated-by-a-libc-pthread."
---

# A foreign thread needs its own TLS block, and the bounds are the hard part

## What is NOT the question

Detection. `feature-a-io-lock-owner-from-tls-not-gettid` shipped the one test
inheritance cannot fake — a thread's own `rsp` against the bounds its block's
owner recorded — and it is live at `ir_codegen.inc:1099-1118`. Anywhere that
needs "am I running on somebody else's block" can ask, with two loads and two
compares and no syscall.

[[bug-a-a-foreign-thread-shares-the-main-thread-s-heap-magazine]] lists
"detect and install lazily" and dismisses it on the detection half. That
analysis predates the discriminator and should not be read as current.

## The question

**Where does a lazily-installed block come from, and what bounds go in it?**

Installing is easy: carve `TLS_BLOCK_SIZE`, zero it, `arch_prctl(ARCH_SET_GS)`.
Everything downstream then works — a private exception chain, a private heap
magazine, private signal slots — because every consumer reads `gs:` and asks no
further questions.

The bounds are what bite, and they bite in a loop:

- **Bounds unset (`HI = 0`)** is the documented fail-safe and every consumer
  handles it: the I/O lock falls through to `gettid`, correct and slower. But
  the install check ITSELF reads the bounds, so the next `try` on that thread
  reads it as foreign again and installs a SECOND block — zeroing a live
  exception chain mid-flight. The fail-safe direction for a fast-path
  optimisation is the unsafe direction for an idempotence test.
- **Guessed bounds** (`rsp - 8MB .. rsp + 64KB`) make the check idempotent and
  make a wrong bound possible, which the parent ticket already names as the
  harder failure: a thread whose real stack is smaller silently passes the test
  while running on a neighbour's block.
- **Real bounds** need the thread's stack VMA — `/proc/self/maps`, or
  `pthread_getattr_np`, which is a libc dependency in the runtime that chose
  `gs` precisely to avoid depending on libc.

A fourth shape worth weighing: **a separate idempotence marker that is not the
bounds** — e.g. the block's own address compared against a value only the
installer could have written there, or a tid cached once at install and checked
only on the install path (where one `gettid` per thread is free) rather than on
every `gs:` read.

## Where to hook it

Also undecided, and cheaper: `try` entry alone bootstraps the whole block for
any thread that ever raises, but not for one that only allocates. The honest
set is probably `try` entry plus the heap fast path.

## Why it matters now

[[the-goal-cross-cross]] names DOSBox. DOSBox, SDL, GTK and every threaded C
library create threads pxx never sees, and
[[bug-a-the-exception-chain-fix-is-defeated-by-a-libc-pthread]] is a measured
crash today: 3 runs of 3 print `Unhandled exception` where the identical work on
one thread in the same binary is clean.
