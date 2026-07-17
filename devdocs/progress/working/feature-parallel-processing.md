---
prio: 45  # auto
---

# Parallel processing as a language feature

- **Type:** feature
- **Status:** working
- **Owner:** A-parallel
- **Blocked-by:** feature-threadsafe-heap-contract
- **Opened:** 2026-06-06 (user request)

## Motivation

Expose parallelism as a first-class language surface, not just raw pthread
binding. Today there is low-level groundwork — `--threadsafe` /
`{$THREADSAFE ON}` emits atomic refcounts, and `test/test_multithreading.pas`
drives raw pthread workers — but no language constructs for spawning and joining
work, sharing data safely, or expressing data-parallel loops.

## Scope (design-open)

Pick a model and a minimal surface; this ticket is the design + first slice:

- **Threads / spawn-join.** A `TThread`-like class or a `spawn`/`sync` pair: start
  a routine on a worker, join/await its result.
- **Synchronization.** Surface mutex / atomic primitives (the `--threadsafe`
  path already emits atomics for refcounts — generalize to user locks).
- **Data-parallel loop** (stretch): a `parallel for` that fans iterations across
  a worker pool, with a clear rule on what's shareable.
- **Memory model.** State what's safe to share vs. copy. Ties to managed-value
  ownership: shared mutable managed values need atomic refcounts (have) plus a
  uniqueness/ownership story (copy-on-write uniqueness checks still need external
  sync today — see `feature-managed-string-default`).

Design context: `../../developer/threads-todo.md` (ordered thread arc),
`../../developer/threading-and-heap-design.md`. The worker-pool / resumable-frame
mechanism can be **shared with** `feature-async-coroutines` (one event loop +
pool, two surfaces) — design them together rather than twice.

## Why blocked

Concurrent allocation needs a proven **thread-safe heap contract** for the active
memory-management mode. The unified allocator has landed, and `--threadsafe`
covers important refcount paths, but Track A still needs to audit/define the
heap behavior for real preemptive threads; see
`feature-threadsafe-heap-contract`. Parallel code doing I/O also wants
`feature-threadsafe-io-serialization` (statement-atomic `write`/`writeln`) — not
a hard blocker, but expect to need it in the same breath.

## ESP32 / FreeRTOS (decided 2026-06-18)

Threads route through the OS/RTOS — **PXX will not ship a bare-metal scheduler**.
Rationale: anyone wanting threads on ESP is, in practice, already pulling in
ESP-IDF for Wi-Fi / BLE / drivers, so threads = **FreeRTOS tasks** (the IDF
profile). See
[developer/concurrency-memory-model.md](../../developer/concurrency-memory-model.md).

- **`threads ⇒ idf`.** A bare program (`--esp-profile=bare`) that uses the thread
  surface is a **hard error** pointing at `--esp-profile=idf`. Bare stays
  self-contained — FreeRTOS must never become a hidden dependency of the bare
  profile.
- **Binding, not syntax.** Expose FreeRTOS task create/join + **optional core
  pin** under the same spawn/join surface, not new keywords.
- **Dual-core SMP.** ESP32 is dual-core (PRO/APP). The "core 0 = networking,
  core 1 = app" split is an IDF pinning **convention, not hardware-enforced** —
  tasks pin to a core or float. Surface the pin as an option on spawn.
- **Memory model.** Each FreeRTOS task is a **statically-sized stack** (no MMU
  growth) — same discipline as a stackful coroutine, chosen at task creation.
- `--threadsafe` already emits atomic refcounts; reuse for the ESP path.

Distinct from the coroutine work: stackless/stackful coroutines are *cooperative*
and the RAM-cheap default for embedded (feature-async-auto-backend /
feature-stackful-coro-port). Threads are the *preemptive multicore* axis and only
make sense on the IDF profile.

## ESP target profile default (related)

Formalise `--esp-profile={idf,bare}` with **`idf` as the default** (≈99% of real
apps use something from IDF) and `bare` a first-class one-flag opt-in (tiny
images, no IDF toolchain, fast language testing under qemu). Tracked here because
the `threads ⇒ idf` rule needs the profile to be an explicit, queryable selector.
Today the IDF path is implied by `.o`/`--emit-obj` output and bare by
`--esp-profile=bare`; unify them under one flag.

## Acceptance

A program spawns workers, joins results, and shares data through the chosen
primitives with correct results under repeated runs (data-race-free for the
covered surface); self-host fixedpoint holds; `--threadsafe` covers the atomic
paths. On ESP: the thread surface compiles+runs under the IDF profile (FreeRTOS
tasks, optional core pin) and is a clear error under `--esp-profile=bare`.

## SHIPPED — `parallel for` (2026-07-17, closing)

Data-parallel loop delivered end to end, self-host byte-identical throughout,
gated in `test-threads`/`test-core`:

- **Runtime** `PXXParallelFor` (libc-free pool) · **surface** `parallel for i := lo
  to hi do BODY` (soft keyword, `AN_PARFOR` node, parse-time worker synthesis).
- **Capture** of enclosing locals via the enclosing frame pointer: scalars (read +
  write-back), named-type fixed/dynamic arrays, records, classes, and ansistring.
  Dyn arrays deref the handle; ansistring is inline-style.
- **Async × parallel VERIFIED compatible** — per-thread coroutine reactors
  (`CurR` keyed on `gettid`); each worker/`TThread` runs its own scheduler.
  Proven (`test_async_parallel_compat.pas`).
- **Fixed a SILENT compiler bug on the way:** [[bug-pascal-ptr-deref-string-index]]
  (`p^[k]`), which also unblocked ansistring capture.

### Accepted limitations (decisions, not defects — every one a CLEAN compile error)
- **Anonymous inline capture types** (`var a: array[0..9] of Integer`): error,
  nudging a named `type`. User-confirmed a non-limitation (one-line workaround).
  B-2 (synthesize a name via re-entrant type registration) is optional polish, not
  planned.
- **Nested `parallel for`**: error, by DECISION (user-agreed 2026-07-17). Outer
  already saturates cores; inner oversubscribes → slower (OpenMP disables nesting
  by default). Real needs = flatten the loop, or a future task API.
- Reduction across >1 worker into a captured scalar is a race (user's
  responsibility); single-worker write-back is deterministic.
- x86-64 only (the PAL); other targets keep the `--threadsafe` reject.

Closed. Remaining epic items live in [[meta-multithreading]].

## Log
- 2026-06-06 — ticket opened from user request.
- 2026-06-18 — ESP/FreeRTOS strategy + `threads ⇒ idf` + profile-default decision
  recorded (design discussion); see developer/concurrency-memory-model.md.
- 2026-06-28 — blocker moved from the completed unified allocator to
  `feature-threadsafe-heap-contract`: refcounting exists in threadsafe mode, but
  heap safety needs an explicit Track A contract per memory-management mode.
- 2026-07-16 — UNBLOCKED (both blockers done: heap-contract + io-serialization).
  Surface decided (user, Track U): **`parallel for`** data-parallel loop as the
  first slice. Lowering = **new AST node `AN_PARFOR` + IR**; capture = **full
  implicit local capture**.

  ### Design (as built)
  **Runtime (STEP 1 — DONE, commit c35e90b3, Track B):** `lib/rtl/palparallel.pas`
  over the M1 PAL. Fixed body ABI:
  ```
  TParForBody = procedure(ctx: Pointer; lo, hi: NativeInt);
  procedure PXXParallelFor(lo, hi: NativeInt; body: TParForBody; ctx: Pointer);
  ```
  Partitions [lo..hi] into contiguous chunks (remainder spread over first chunks),
  chunk 0 runs inline on the caller (no idle spawn), rest spawn via PalThreadCreate,
  barrier-join. Worker count = sched_getaffinity popcount clamped [1..64],
  overridable (PXXSetParForWorkers). Empty range = no-op; spawn failure falls back
  to inline. Test `test_parallel_for.pas` drives it directly (exact partition:
  every index once; values; edge ranges) — gated in `test-threads`.

  **Parser + IR (STEP 2 — in progress, Track A/P, shared parser.inc):**
  ARCHITECTURE FINDING: this compiler mints helper procs ONLY at parse time
  (lambda-lift + stackless-generator both token-transform in the parser); there is
  no path to synthesize a proc during IR lowering. So AN_PARFOR reconciles the two
  choices as: a first-class node whose *parse action* uses the lambda-lift token
  machinery to synthesize the worker proc `__pf_K(ctx, lo, hi)` + capture, whose
  *IR lowering* emits the `PXXParallelFor(lo, hi, @__pf_K, @ctx)` call.
  - **2a (capture-free):** body may reference loop var + globals only; an enclosing
    local ref is a clear error. Worker synthesized as a capture-free stashed proc.
    Green intermediate (compiler self-build uses no `parallel for` → byte-identical).
  - **2b (full capture):** extend the lift capture scan to pack captured-by-ref
    locals into a synthesized ctx record; worker reads `PCtx(ctx)^.field^`; call
    site fills ctx from `@local`s. This is the large piece (extends the delicate
    lambda-lift machinery).
  - `parallel` = soft keyword recognized only immediately before `for`. `downto`
    rejected (order-independent). Requires `--threadsafe` (compile error like
    `__pxxclone`, since the body may alloc). Off-unless-used ⇒ self-host gate holds.

- 2026-07-16 (cont.) — **STEP 2a SHIPPED** (commit e3f52d73). `parallel for`
  capture-free: soft keyword, worker synthesis (forward-reg via re-entrant
  ParseSubroutine + pass-2 flush), `AN_PARFOR` node, IR lowering to the runtime
  call. Self-host **byte-identical**; `quick` + full `test-threads` green.
  LANDMINE fixed mid-build: the body-token stash must copy the FULL TRawToken —
  copying only Kind/SOffset/SLen zeroed `IVal`, so every integer/float LITERAL in
  the body silently became 0 (`a := 99` → `a := 0`). Verbatim record copy fixes it.
  Extended-tested: method bodies, multiple `parallel for` in one routine, 2M-element
  workload (correct), and the guards (downto / main-body / no-`uses` / no-`--threadsafe`).
  Gates: `test_parallel_for.pas` (runtime) + `test_parallel_for_lang.pas` (surface)
  + a no-threadsafe error probe.

  **v1 LIMITS (all clean compile errors, not miscompiles):** body captures the loop
  var + globals only (enclosing-local capture rejected); must be inside a routine
  (main program body has no nested-proc flush point); `to` only. Nested `parallel
  for` sharing the outer index needs capture (2b).

  ### 2b Phase A — SCALAR capture SHIPPED (2026-07-16, commit 9fe36832)
  Enclosing-local capture, scalars first, via the **frame-pointer** trick (much
  simpler than a ctx record): ctx = the enclosing routine's frame pointer
  (`AN_FRAME` at the call site); the worker reads each captured scalar at
  `ctx + Syms[si].Offset` through a synthesized `capj: ^T; capj := Pointer(
  NativeInt(ctx) + off)` preamble, and every captured reference in the body gets a
  postfix `^` (`a`→`a^`, `a:=x`→`a^:=x`). No container, no fill — one pointer.
  Read + write-back both work (`test_parallel_for_capture.pas`, gated). Scalar type
  → `^T` keyword via `PFScalarKw`. Nested `parallel for` rejected cleanly (peek the
  body span before it recursively desugars). Reduction across >1 worker is a race
  (user's responsibility); single-worker write-back is deterministic. Self-host
  byte-identical.

  ### 2b B-1 — NAMED-type aggregate capture SHIPPED (2026-07-16, 84e74646 + 122552c8)
  Capture of enclosing locals with a NAMED type (fixed array, dynamic array,
  record, class), on the Phase-A frame-pointer mechanism. Worker names its
  accessor `capj: ^<TypeName>` and reads at `ctx + Syms[si].Offset`. Exact
  fidelity — reuses the SAME declared type, no reconstruction.
  - **Type-name recovery:** new parallel array `SymDeclTypeNOff/NLen` records a
    single-named-type span at var-decl time (ParseVarSection); reset in EVERY
    `Alloc*` (Var/Param/Array/DynArray) so a recycled slot can't leak a stale name
    ([[project_symtab_alloc_parallel_array_landmine]] discipline). Self-host stayed
    byte-identical — landmine handled.
  - **Handle types:** a dyn array / ansistring slot holds a DATA POINTER, so the
    worker derefs once more: `capj := Pointer(PNativeInt(ctx+off)^)` vs inline
    `capj := Pointer(ctx+off)`. Found by disasm (a `^TDyn` indexes off the data
    base, but the frame slot holds the handle). `capHandle` flag branches it.
  - **Array-scalar-path fix (122552c8):** an array var's TypeKind is its ELEMENT
    type, so arrays were masquerading as scalars (anon fixed "worked" by accident;
    anon dyn crashed). Guarded — arrays route to the named path or a clean error.
  - Covers the flagship `parallel for i do a[i]:=f(a[i])` with a local **named-type**
    array (fixed or dynamic). `test_parallel_for_capture_aggr.pas` gated.

  ### 2b ansistring capture SHIPPED (2026-07-17, commit 08e987c9)
  Unblocked by fixing [[bug-pascal-ptr-deref-string-index]] (a SILENT compiler bug
  the capture surfaced: `p^[k]` char-index through a pointer-to-string deref read
  the frame-slot bytes, not the char data — `ir.inc` AN_INDEX took baseAddr from
  IRLowerAddress (slot) instead of the loaded handle for a deref base). With that
  fixed, the worker's `^AnsiString` + `s^[k]` is correct; ansistring capture works
  (Length + char-index + compare, `test_parallel_for_capture_string.pas`, gated).
  Ansistring is INLINE-style (frame slot holds the handle, `@s` = slot,
  capHandle=false) — distinct from a dyn array (`@d` = data, capHandle=true).

  ### 2b B-2 — ANONYMOUS-type capture (remaining, optional)
  `var a: array[0..9] of Integer` (inline, unnamed) still errors: "declare it with
  a named type". Workaround is trivial (`type TA = array[..]; var a: TA`) and
  arguably good practice. Proper fix = record the anonymous type's TOKEN span at
  decl and synthesize `type __pft_n = <copied tokens>` via re-entrant type-section
  parse (exact fidelity, per the copy-source-tokens insight). Real machinery for a
  case with a clean error + one-line workaround — deferred as polish.


  Same frame-pointer mechanism; the ONLY gap is naming `^Tj` for the worker's typed
  accessor. Findings:
  - inline `^array[..] of T` / `^array of T` is NOT valid pxx syntax — pointer
    targets must be NAMED types (`pn: ^TA` works).
  - a var's declared type-alias NAME is not retained on `TSymbol` (only the resolved
    `TypeKind`/`IsArray`/`ArrLen`/`ElemType`), and class/record names aren't a cheap
    lookup either. So `^Tj` can't be reconstructed from symbol info today.
  - **Two ways forward (the fork):** (a) record the declared type-name on the sym
    (a parallel-array add — mind the Alloc*-reset + [[project_tsymbol_field_landmine]]),
    then `^<that name>` uniformly covers arrays/records/strings when the local uses a
    NAMED type (anonymous → error nudging a `type` decl); or (b) synthesize+register
    a reconstructed type (`type __pfat_n = array[0..N-1] of T`) via the same
    re-entrant parse used for the worker forward decl. (a) is smaller and also good
    practice pressure; (b) handles anonymous types too. The flagship local-array case
    needs whichever lands.
  Currently a clean compile error: "capturing enclosing array/non-scalar … (Phase B)".

  ### 2b (original full-capture ctx-record design — superseded by the frame-pointer trick)
  The thread-boundary worker MUST take exactly `(ctx, lo, hi)` — lambda-lift can't
  cross it (any routine touching a capture gains by-ref params, breaking the fixed
  ABI). So captures funnel through one `ctx` pointer, unpacked manually in the worker:
  - collect distinct captured locals from the body scan (the 2a reject-scan already
    finds them — collect instead of erroring);
  - pass by-ref: synthesize an enclosing-frame `__pfc: array[0..k-1] of Pointer`,
    fill `__pfc[j] := @capj` at the call site, pass `@__pfc[0]` as ctx;
  - worker declares `capj: ^Tj`, preamble `capj := PPointer(ctx)[j]`, and every
    captured use `a` gets a postfix `^` (uniform: `a[i]`→`a^[i]`, `a:=x`→`a^:=x`,
    like lambda-lift's field-prefix insertion);
  - the one hard sub-problem is **reconstructing `^Tj` as tokens** from TSymbol
    (scalars + named record/class + dynamic array + string are nameable; inline
    fixed-array types are not — error there in 2b-v1). Reference types (dyn array /
    string / class) MAY instead capture by value (handle copy shares storage).

  ### Async × parallel — COMPATIBILITY VERIFIED (2026-07-16)
  Inventory of the two concurrency models and whether they compose:
  - **parallel** (this ticket / M1-M3): preemptive OS threads (`clone`/`futex`),
    multicore, `TThread` + `parallel for`, needs `--threadsafe` (atomic ARC + locked
    heap/IO). Real parallelism.
  - **async** ([[feature-async-coroutines]] / [[feature-async-language-surface]]):
    cooperative stackful/stackless coroutines, single-threaded concurrency,
    `Spawn`/`CoYield`/`await`/`RunUntilDone` + epoll reactor. NOT parallelism.
  - **They compose cleanly.** `scheduler.pas` `CurR` keys each thread's reactor on
    the kernel tid (`gettid`), attaching a per-thread slot under an atomic spinlock
    ("per-thread state without threadvar"). Generators are per-instance
    (`coroutine.pas`, state in a passed heap block). So every `parallel for` worker /
    `TThread` runs its OWN independent coroutine scheduler; the spinlock's
    `__pxxatomic_cas` is exactly what `--threadsafe` (required by `parallel for`)
    provides. PROVEN: `test/test_async_parallel_compat.pas` — 400 coroutines fanned
    across 8 worker threads, each yielding on its own reactor, all correct
    (`ASYNC x PARALLEL OK`), gated in `test-threads`.
  - **The invariant (document in user docs):** a coroutine/reactor is bound to the
    thread that created it — never resume the SAME coroutine, or drive one reactor,
    from two threads. `await`/`CoSleep` inside a `parallel for` body run on the
    WORKER's reactor, not the main thread's. Within the natural "each thread owns its
    coroutines" model they are fully compatible; cross-thread coroutine handoff is not
    supported (and not needed — that's what the thread surface is for).

## Part of the multithreading epic (2026-06-30)

Umbrella: [[meta-multithreading]]. Invariant: threading is opt-in/off-by-default;
single-threaded self-build stays byte-identical; no libc (Linux syscalls only).
