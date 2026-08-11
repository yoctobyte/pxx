# The pxx threading model — and why it is not CPython's

Written 2026-08-11, from the Track U session that settled
`decide-nilpy-parallel-capture-semantics`. This is the reference for what
`--threadsafe` guarantees, what it must guarantee, and how NilPy's position
differs from CPython's.

The short version: **CPython spent four years paying back a debt we never took
out.** Almost none of PEP 703 applies to us. One piece does, and it is the piece
this document exists to name.

---

## 1. What the GIL actually was

Not a parallelism mechanism — a **memory-management** one. CPython manages
objects by reference counting, and every attribute access, argument pass and
loop iteration touches `ob_refcnt`. Make those atomic and you pay a locked
instruction on essentially every operation in the language, plus cache-line
contention on hot shared objects like `None`. The GIL made refcounting free by
making it single-threaded.

Container integrity and C-extension safety came along as **side effects**. So
did a third thing people actually noticed: because the interpreter switched
threads only at bytecode boundaries, many user-visible operations turned out to
be atomic — `list.append`, `d[k] = v`, `x = L[i]`. That was **emergent, never
promised**; `x += 1` was not atomic even under the GIL.

## 2. What replaced it (PEP 703), and why none of it is ours

Four mechanisms, all aimed at making refcounting cheap again without breaking
thirty years of C extensions:

| mechanism | purpose | applies to pxx? |
| --- | --- | --- |
| **biased reference counting** | owner-thread increfs stay non-atomic; other threads use a shared counter | **no** — our refcounts are emitted inline by codegen; `--threadsafe` already emits `lock dec` |
| **immortal objects** (PEP 683) | `None`/small ints/interned strings get a saturating refcount, never written | **already had it** — FPC's constant strings carry refcount −1; we reserved `PXX_FLAG_STATIC` |
| **critical sections** | a per-object lock that *releases on blocking*, so existing C code becomes safe by wrapping rather than auditing | **no** — no retrofit corpus, no interpreter loop, no suspension points |
| **mimalloc + lock-free reads** | thread-safe allocation enabling optimistic container reads | **no** — we have our own allocator behind one spinlock |

We have no interpreter state, no global lock, no C-API contract, and no cycle
collector (so free-threading's whole stop-the-world-GC chapter is absent —
at the known separate cost that cycles leak).

**Pascal was ahead on one of them.** PEP 683's immortal objects, landed in 2021,
are FPC's constant-string trick. We should stop treating `PXX_FLAG_STATIC` as an
optimisation to justify; it is the mainstream answer.

## 3. Where we are structurally ahead

**Static types make private-by-default real, at the machine level.** Most NilPy
values are unboxed — in registers, on the stack — per-thread by construction,
with no refcount and no sharing. CPython boxes everything, so *every* value is
potentially shared and needs the whole apparatus.

Our actual sharing surface is only **managed blocks reachable from a name
captured by a parallel body**. Small, and statically identifiable. Theirs is the
entire heap.

This is why the NilPy capture question had a better answer than CPython's: the
thing needing a policy was never "objects", it is containers reachable from a
parallel body. Everything else is private without anyone deciding anything.

## 4. Where a Pascal assumption leaves us BEHIND — the one real gap

**`--threadsafe` today makes the RUNTIME safe, not the DATA STRUCTURES.**

What it covers: the allocator spinlock (`__pxxatomic_xchg(@PXXHeapSpin, 1)`),
atomic refcounts (`lock dec qword [rax-16]`), statement-atomic console I/O
(`IR_IO_LOCK`). x86-64 only — `builtinheap.pas:1555` states the refcount blob is
non-atomic on other targets, so **any parallel story is single-target until that
moves.**

What it does not cover — `TPyList.append_self`, in full:

```pascal
PyListGrow(Self, FLen + 1);                        { may REALLOC FItems }
dst := PPyVarRec(NativeInt(FItems) + FLen * 16);
PyVarSlotSet(dst, src);
FLen := FLen + 1;                                   { read-modify-write }
```

Two threads appending: the benign outcome is a lost element (both read
`FLen = n`, both write slot `n`). The malignant one is `PyListGrow` reallocating
under thread B while thread A holds the old `FItems` — **a use-after-free in the
container runtime.**

Free-threaded CPython *guarantees* this cannot corrupt. You may lose the update;
you may not lose the heap. That is the gap, and it comes straight from a Pascal
assumption: in Pascal a shared mutable structure is the programmer's problem,
full stop — dynamic arrays are not thread-safe and nobody expects them to be.
NilPy inherits that stance **silently**, and a Python programmer's baseline is
now strictly stronger than a Pascal programmer's.

### The line we adopt — CPython's, deliberately

- **Data-structure integrity is the runtime's job.** No corruption, no
  use-after-free, no torn structures. Ever.
- **Logical atomicity is the user's job.** `d[k] += 1` racing loses updates.
  Always did in Python, always will.

Note what this is and is not: CPython gives an **operational guarantee from one
implementation**, not a specification. *There is no Python memory model* — no
happens-before edges, no account of what a racy program may do. We can copy the
guarantee; we cannot derive the corner cases from it.

### The surface is two classes

`TPyList` **is** list, tuple *and* set (`setupdate`, `setintersect`, `issubset`,
`union`, `symmetric_difference` all hang off it); `TPyDict` projects into it
(`itemlist`/`keylist`/`vallist`). The entire container-integrity surface is two
classes. See `feature-nilpy-threadsafe-containers`.

### The one-way rule — learn from HotSpot, not just from CPython

The intended optimisation is to pay only when an object is genuinely shared:
owner-thread fast path, lock only after a second thread touches it. That is
**biased locking**, and it has both a success and a failure story.

CPython's biased *reference counting* works. HotSpot's biased *locking* was
disabled in JDK 15 and removed in 18 — and **the fast path was never the
problem; revocation was.** Un-biasing an object required global coordination,
and as core counts and object churn rose, revocation cost more than the bias
saved.

So the rule, and it is not negotiable:

> **"Becomes shared" must be one-way and purely local.** A container flips from
> owner-fast to locked once, forever. No revocation, no global coordination,
> never flip back.

Monotone means a plain `if FOwnerTid <> CurrentTid then FShared := True` on
entry: one predictable branch, no barrier in the common case, and the worst
outcome is a container that stays locked after sharing stops. Which is fine.

Storage: **not** the managed-block meta word — its low 32 bits are fully
allotted (`BlockKind|Flags|KindData0|KindData1`) and bits 32–63 are reserved for
`feature-a-shrink-managed-header-on-32-bit`. `TPyList`/`TPyDict` are Pascal
classes with their own fields; put `FOwnerTid`/`FShared` next to `FLen`. Eight
bytes per container, zero header-budget pressure.

## 5. Monothreaded compilation is a FEATURE, not a limitation

CPython's opt-out is a **build and ABI split** — `cp313t`/`cp314t` wheel tags,
extensions declaring GIL support, an ecosystem shipping two of everything. A
library author there cannot offer "zero overhead if you don't need it"; they
ship both artifacts.

Ours is a compile-time flag over the **same source**, with no ecosystem to
fragment. That is the payoff for being a compiler: they had to make
free-threading a build because they could not recompile the world. We recompile
the world every time.

So we can afford a *more* conservative default than CPython could, and should:
single-threaded programs pay **nothing**, and that is a deliberate design
commitment, not an unfinished migration.

### Corollary: `--threadsafe` means the WHOLE contract

Container locking belongs under the **existing** flag. Do not add a second one.
A mode where the allocator is safe but your lists still corrupt is the worst
available point on the dial: it reads as a safety guarantee and is not one. One
flag, one meaning — *"this program may use threads and the runtime will not
betray you."*

## 6. `parallel for` is a different question, and deliberately so

Nothing above auto-parallelises anything. **PEP 703 did not give CPython
parallelism either — it stopped preventing it.** You still spawn threads by
hand.

The same split holds here, and it is the reason the capture semantics and the
container safety are separate tickets:

- **threading compatibility** — can a program that shares a list across threads
  survive? Runtime's job.
- **`parallel for`** — should the compiler fan a loop out? The programmer's
  call, always. Making linear code parallelisable and declaring a whole loop
  embarrassingly parallel are different problems, and which applies is an
  application fact the compiler cannot know.

`parallel for` is also the **one corner of NilPy where restrictions are free.**
The upward-compatibility rule runs one direction — *if code works on CPython it
must work on NilPy* — and no CPython program contains a `parallel for`. So a
limitation there cannot break a working program, which is what licenses the
native-int reduction default in `feature-nilpy-parallel-for-in`.

## 7. Open

- `--threadsafe` is **x86-64 only**. Hard limit or unfinished work? Nobody has
  asked. It bounds everything above.
- No measurement exists of ARC contention/false sharing on a shared managed
  value under `--threadsafe`. A parallel loop reading one shared list still
  hammers one refcount line from every core. Before promising scaling to anyone,
  benchmark it.
