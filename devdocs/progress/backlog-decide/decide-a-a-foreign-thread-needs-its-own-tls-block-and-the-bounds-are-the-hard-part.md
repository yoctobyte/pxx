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
summary: "DETECTING a foreign THREAD is solved for the case the shipped I/O-lock discriminator asks about -- the reader's own rsp against the bounds the block's owner recorded, live in ir_codegen.inc. It is NOT sufficient for the question this ticket needs answered. Measured 2026-09-02: a pxx stackful generator body runs on a HEAP stack (lib/rtl/coroutine.pas CoAlloc GetMem(65536)), 13TB from the thread's own frame, so every rsp test reads a running generator as foreign. For the I/O lock that is fail-safe (fall back to gettid); for an IDEMPOTENCE test it is fail-unsafe -- it would install a fresh block on every generator entry and zero the live exception chain, the exact failure this ticket attributes to HI=0, reached by a construct that ships and is tested today. So the open question is where a lazily-installed block comes from AND what marker says "already mine", and the marker cannot be an address. Also measured: the widening-observed-rsp-window option was excluded here on a reason that does not hold (0 of 6 pairwise overlaps with threads using 99.15% of their stacks); it is excluded by the generator stack instead. This blocks a program that fails today: bug-a-the-exception-chain-fix-is-defeated-by-a-libc-pthread."

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

## 2026-09-02 (frankA) — measured: glibc packs thread stacks with NO margin, which refutes two of the four options by arithmetic

The bounds question has a number attached to it and nobody had taken it. On
this box (glibc, `ulimit -s` 8192):

```
main    rsp=0x7ffce34e32cb
worker 0  hi=0x79d1bd1fee83  lo=0x79d1bcad9c50  own-range=7492147 bytes
worker 1  hi=0x79d1bc9fde83  lo=0x79d1bc2d8c50  own-range=7492147 bytes
worker 2  hi=0x79d1bc1fce83  lo=0x79d1bbad7c50  own-range=7492147 bytes
gap w0->w1 = 8392704 bytes
gap w1->w2 = 8392704 bytes
MARGIN between w1's own observed range and w2's top = 900557 bytes
```

**Consecutive live pthread stacks are exactly 8392704 bytes apart** — 8MB plus
one 8KB guard page — and they are CONTIGUOUS, not scattered. `main` is about
140GB away from all three, which is why the shipped I/O-lock discriminator works
today: it only ever has to tell main from a worker, and pxx-created threads get
exact bounds from the clone stub.

### This refutes the guessed bounds, by their own numbers

The option above proposes `rsp - 8MB .. rsp + 64KB`. **8MB is exactly the stack
size**, so from a shallow `rsp` that window's lower edge lands in the
NEIGHBOUR's stack — the failure the parent ticket calls "the harder failure",
reached not by an unusual thread but by the default one. Any guess large enough
to cover a full stack is large enough to cover the next thread's.

### And it refutes the widening-window shape, which is worth stating because it looks sound

A fourth-option variant that suggests itself: install with the bounds unset,
then instead of reinstalling, WIDEN a `[minObservedRsp, maxObservedRsp]` window
each time the thread is seen. It looks sound — different threads have disjoint
stack VMAs, so a window covering only addresses this thread actually touched can
never contain another thread's `rsp`.

**The margin measured is 900557 bytes and that is an artefact of my probe
stopping at 1800 frames**, i.e. 7492147 of the 8388608 bytes available. A thread
that uses its whole stack has a window that reaches the guard page, and the
neighbour's stack begins immediately on the other side of it. The scheme is
sound only while every thread stays strictly inside its stack, which is not a
property the runtime can assume of a program it did not write. It also breaks
outright on the sigaltstack, which the existing discriminator's comment already
handles as a deliberate miss.

So the residual shrinks: **an idempotence marker must be something other than an
address range.** The tid cached at install and compared only on the install path
survives this measurement; the two address-based shapes do not.

### The probe, and the confound it caught first

```c
static void rec(int id, int d) {
  volatile char pad[4096];
  unsigned long r = (unsigned long)&pad[0];
  pad[0] = (char)d;
  if (r < lo_seen[id]) lo_seen[id] = r;
  if (r > hi_seen[id]) hi_seen[id] = r;
  if (d > 0) rec(id, d - 1);
}
```
with each worker recording `hi`/`lo` around `rec(id, 1800)`.

**Create all threads before joining any.** The first version created and joined
one at a time, and all three reported byte-identical `hi` and `lo`: glibc caches
and reuses a dead thread's stack, so the gap this probe exists to measure was
exactly zero and read as a finding. The reused stack is a real fact about glibc
and it is not the fact the question needed.

Not a recommendation: no option is chosen here and no code changed. What is
added is that two of the four are now arithmetically excluded rather than
weighed.

## 2026-09-02 (frankA) — the rsp marker is defeated by pxx's OWN generators, and the widening-window exclusion was right for the wrong reason

Two measurements. The second matters more than the first.

### 1. The widening-window exclusion does not hold as stated

The section above excludes the widening `[minObservedRsp, maxObservedRsp]` marker
because *"a thread that uses its whole stack has a window that reaches the guard
page, and the neighbour's stack begins immediately on the other side of it."*
Reaching the guard page and CONTAINING a neighbour's `rsp` are two different
claims, and only the second is the failure. Measured, four pthreads each
recursing until 64KB from their own known floor (`pthread_getattr_np`, so the
stop is not a guess), all created before any is joined:

```
w0 vma=[0x7cd89fa00000,0x7cd8a0200000) size=8388608  seen span=8317056  unused-below-seen=64896
w1 vma=[0x7cd89f1ff000,0x7cd89f9ff000) size=8388608  seen span=8317056  unused-below-seen=64896
w2 vma=[0x7cd89e9fe000,0x7cd89f1fe000) size=8388608  seen span=8317056  unused-below-seen=64896
w3 vma=[0x7cd89e1fd000,0x7cd89e9fd000) size=8388608  seen span=8317056  unused-below-seen=64896
pairwise overlaps=0 of 6 pairs
positive control (w0 vs itself) overlap=1 (must be 1)
```

99.15% of each stack touched, **zero overlaps**. An observed window is a subset
of its own VMA by construction, consecutive VMAs are separated by a 4096 guard
page, so a neighbour's `rsp` cannot be inside one. The stack-REUSE hazard does
not rescue the exclusion either: a thread's stack is allocated at
`pthread_create`, i.e. while its creator is still alive, so a child cannot land
on the parent's stack — tested directly, 3 runs of 3, the child got a different
VMA every time (while four sequential create/join threads got the byte-identical
VMA every time, which is the reuse the earlier probe tripped over).

**This is not an argument to adopt the widening window.** It is an argument that
the reason recorded for excluding it was falsifiable and false, and a false
exclusion in a decide ticket is worse than an open option: the next reader
checks it, finds it wrong, and reopens the wrong door.

### 2. The reason that does hold, and it ships today

**A pxx stackful generator body runs on a HEAP stack.** `lib/rtl/coroutine.pas`
`CoAlloc` does `GetMem(CO_STACK)` — 65536 bytes — builds the initial saved-state
frame there, and `CoSwitch` runs the body on it. Measured:

```
procedure frame  = 140732946248072
generator frame  = 127672537645112
distance         = 13060408602960 bytes (~13 TB)
```

So **inside a running generator, every rsp-against-stack-bounds test says
"foreign"**, on the thread that owns the block, with no foreign thread anywhere
in the program.

For the shipped I/O-lock discriminator this is harmless and already accounted
for: a miss falls through to `gettid`, which is correct and slower. **For an
idempotence test the same miss is the unsafe direction** — it would install a
fresh TLS block on every generator entry and zero the live exception chain,
which is exactly the failure this ticket attributes to `HI = 0`, reached not by
an edge case but by a construct that ships, is documented (`docs/library/async.md`)
and is tested (`test_coswitch.pas`, `test_scheduler_exc.pas`,
`test_residency_coswitch.pas`).

And the two mechanisms already interact: `CoAlloc` writes `exc_top := 0` into
the generator's initial frame — *"fresh chain on this stack"*. The exception
chain is ALREADY per-stack rather than per-thread wherever a generator is
involved, which is a second reason not to build its ownership test out of a
stack address.

### What this leaves

**An idempotence marker must be something no stack switch can move.** Every
address-based candidate in this ticket is one that a stack switch moves, and pxx
switches stacks itself. The `gettid`-at-install marker survives both
measurements; `rsp` survives as a fast-path FILTER only, and only where a miss
is fail-safe.

That also sharpens the hook question above. `try` entry was offered as the
cheap hook — and generators are precisely where `try/except` runs on a stack the
thread does not own, so the hook and the defeated marker meet at the same site.

Still not a recommendation: no option is chosen here and no code changed. Three
of the address-based shapes are now excluded on a reason that is measured rather
than argued, and one exclusion already in the ticket has been corrected.
