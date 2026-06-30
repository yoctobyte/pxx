# Audit: shared-global state — reentrancy & thread-safety

- **Type:** audit / tracking (umbrella) — Track A
- **Status:** backlog
- **Opened:** 2026-06-30
- **Found by:** review while shipping decl-order gating (pin v93). One stray-bind
  bug ([[project_decl_order_global_gating_done]]) led to auditing every place the
  compiler forces a `skGlobal` allocation or uses a fixed BSS scratch slot.

## Scope

The compiler emits some per-call/per-site state as **program globals** (one shared
BSS slot) rather than stack locals / caller-provided buffers. Two failure modes:

- **Reentrancy** — recursion clobbers the slot mid-use. Bites even single-threaded
  (can affect the compiler itself).
- **Thread-safety** — concurrent execution races the slot. Bites only under
  `--threadsafe` / a real thread runtime.

This ticket is the index; each concrete item has (or gets) its own ticket.

## Findings

### Reentrancy (worse — single-threaded recursion)
- **Frozen-string function `Result` is a shared global.** Returns the address of a
  global BSS slot; recursion overwrites before the caller copies out. Fix = the
  hidden-destination aggregate-return path. → [[bug-frozen-string-result-global-not-reentrant]]
  (fix proposal written). **Highest priority** of this set — it can miscompile
  ordinary recursive string code, not just threads.

### Thread-safety (concurrent only)
- **Variant-boxing temporaries are shared globals.** `AllocVar('',tyVariant)` with
  `CurProc:=-1`, one slot per source site. Fix = make it a routine local. →
  [[bug-variant-boxing-temp-global-shared]]
- **Console I/O scratch** (`BSS_LINE_BUF`/`INTBUF`/`PEEK_*`/`LINE_POS`/`LINE_LEN`) —
  writeln/readln line + int-format buffers are global; concurrent I/O races. →
  [[feature-threadsafe-io-serialization]]
- **Heap allocator** — guarded by the `--threadsafe` spinlock (x86-64); broader
  per-mode contract → [[feature-threadsafe-heap-contract]]. Pthread surface →
  [[feature-syscall-pthread-shim]].
- Layout/RTTI managed helpers — already addressed →
  [[bug-threadsafe-layout-rtti-helper-races]] (done).

### Intentional (NOT bugs)
- **C `static` locals** (`cparser.inc`, `CLocalStaticDecl` → `CurProc:=-1`) — C
  semantics mandate one process-global instance; thread-unsafe by definition, like
  any C static. Leave as-is.

## Method to find more

Grep choke points: `CurProc := -1` (forced-global AllocVar/AllocArray sites),
`BSS_*` fixed scratch slots, and any `Kind := skGlobal` override. Each new forced
global is a candidate — classify reentrancy vs thread-only by whether a call can
occur between the write and the read of the slot.

## Acceptance

- Every forced-global in the list is either fixed (own ticket) or justified as
  intentional and documented here.
- A `make test` (and, once a thread runtime lands, a threaded) guard for each fix.

## Notes

- Order of attack suggested: frozen-string Result (reentrancy, can bite now) →
  variant-box temp (cheap) → I/O serialization (needs the thread runtime anyway).
- Not blocking the FPC cold-bootstrap work, which is a separate codegen-divergence
  bug ([[bug-fpc-seeded-binary-runtime-segfault]]).
