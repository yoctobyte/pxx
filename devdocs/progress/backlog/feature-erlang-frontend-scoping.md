# Erlang frontend — scoping only

- **Type:** feature — scoping ticket (Track A, once picked up)
- **Status:** backlog — scoping only, no code, not greenlit
- **Owner:** —
- **Opened:** 2026-07-05 (user decision — prioritized ahead of [[feature-zig-frontend]] (parked))
- **Priority:** unranked

## Reframed under the esoteric-frontend-probe category (2026-07-05)

The full-language scoping below still stands, but a **skeleton-only pass**
(lexer/parser for a trivial subset, lowering onto existing IR, no scheduler/
GC work) is separately in scope as a bug-probe against shared internals — not
to make Erlang usable. See [[feature-esoteric-frontend-probes]] for the
category rule.

## Motivation

User chose Erlang over Zig as the next frontend to *scope* (not necessarily
build first — Rust is already in progress).

**Correcting the original rationale (2026-07-05):** the first cut of this
ticket justified the choice as "Zig risks determinism, Erlang doesn't." That
doesn't hold up — see [[feature-zig-frontend]]'s corrected "Why parked" section.
Recursion/Turing-completeness in a comptime interpreter is a *termination* risk
(bounded by a step quota), not a determinism one, and it can't touch the
compiler's own self-host fixedpoint gate since it only runs while compiling Zig
source. Meanwhile Erlang's actor model — preemptive scheduling, message
ordering across processes — is itself a classically *nondeterministic runtime
execution model*. If determinism were the metric, Zig would win, not lose.
Determinism is not why Erlang is worth scoping.

**The real reason:** Zig and Erlang are hard in genuinely different domains.
Zig's cost is concentrated in one place (a comptime interpreter/CTFE engine)
that is pervasive but at least *conceptually contained*. Erlang's cost is
spread across the *runtime* — but the memory-management part of that cost is
**smaller than first estimated** (see "GC gap sizing, corrected" below); the
scheduler is where the real open work is. Not "syntax sugar and hashing" either
way — the syntax (pattern matching, immutability, tuples/atoms/maps) is the
easy part, same as Zig's type theory was the easy part of Zig — but the
remaining hard part is now sized as *one* genuinely novel piece (the
scheduler), not two.

**This ticket is scoping only** — same posture as the original Rust/Zig
umbrellas before any code: map Erlang's constructs onto existing/needed IR,
identify what's free vs. what needs new shared machinery, before committing to
a build.

## GC gap sizing, corrected (2026-07-05)

Original cut of this ticket claimed per-process GC was "plausibly the single
largest item in this whole ticket, bigger than the scheduler itself," reasoning
by analogy to BEAM's own implementation (per-process generational **copying**
GC). That analogy doesn't transfer cleanly and overstated the gap:

- **Erlang term data is immutable — no in-place mutation exists in the
  language.** A cell can never be made to point back at something built after
  it, so ordinary Erlang terms (tuples, lists, maps, records) are **acyclic by
  construction**. Reference counting's one structural weakness is cycles;
  Erlang's own semantics rule cycles out for term data. (Caveat: closures/`fun`
  capturing mutable process state and ETS tables are separate mechanisms with
  their own lifetime rules — scope those explicitly when this ticket is
  picked up, don't assume the acyclic argument covers them.)
- **PXX already has a proven refcounting mechanism to extend, not invent.**
  Managed strings AND dynamic arrays both already use compiler-emitted
  retain/release codegen (`PXXDynArrayRelease` and friends, `compiler/
  ir_codegen.inc`) — this is a working, tested pattern, not a green-field
  design. Extending it to new managed-term types (tuples/lists/maps) is
  plausible reuse of existing machinery, the same way the C frontend reused
  the existing IR/backend rather than inventing a new one.
- **Revised sizing: refcounting (extend existing infra) is the leading
  candidate for Erlang term memory management, not a new tracing/copying
  collector.** This does NOT require the precise stack-map/safepoint
  infrastructure that `feature-handle-compacting-heap.md` explicitly rejected
  as dangerous — refcounting reclaims at the point a count hits zero, no
  stop-the-world root-scan needed.
- What's still genuinely open, and should be sized when this is picked up: the
  cost of per-word refcount inc/dec on immutable data that's copied (not
  mutated) far more often than strings are in typical Pascal code — Erlang
  workloads share/pass terms constantly, so refcount traffic volume needs
  measuring, not assuming free. Also open: whether "shared-nothing, copy on
  send" message passing still makes sense under refcounting (it can — copying
  is about isolation/safety across processes, not a GC-technique dependency)
  or whether refcounted terms could be shared read-only across processes
  instead (a real design choice, not resolved here).

**Net effect on where the hard part sits:** moved from "two roughly-equal
unknowns (scheduler + GC)" to "one clearer unknown (the scheduler), one
probably-tractable-via-reuse item (memory management)." This makes Erlang
*more* realistic than the original sizing suggested, not less — flag this
explicitly so it isn't rediscovered the hard way later.

## Known hard parts, unscoped (fill in when picked up)

- **Pattern matching** as the primary control-construct (not just `case`/`switch`
  sugar — Erlang function clauses dispatch by pattern, including on message
  receive). Likely shares the generalized tagged-union / pattern-match primitive
  already needed by Rust ([[feature-rust-match-enum-payload]]) and Zig — a
  second consumer would justify building it sooner.
- **Immutability** — Erlang has no mutable variables at all (single-assignment).
  Different discipline than PXX's IR assumes; needs its own scoping pass, not
  free.
- **Actor model / message passing** — processes (green, millions-scale, BEAM-
  style), mailboxes, `receive` with pattern + optional timeout. Needs a
  scheduler; closest existing PXX machinery is the stackful coroutine runtime
  (`coroutine_emit.inc`), but BEAM's preemptive (reduction-counted) scheduling
  is a different model than cooperative coroutines — gap needs honest sizing,
  not assumed-free.
- **Per-process memory management** — smaller gap than first estimated; see
  "GC gap sizing, corrected" above. Erlang term data is immutable and therefore
  acyclic by construction, so refcounting — already built and proven for PXX's
  managed strings/dynarrays — is the leading candidate, not a new tracing/
  generational collector. Still open: refcount-traffic cost under Erlang's
  copy-heavy workloads, and whether "isolated heap, copy-on-send" still makes
  sense or whether refcounted terms could be shared read-only across
  processes. Size these two specifically when picked up — don't re-default to
  "needs a full GC" without checking the acyclic argument first.
- **Supervision trees / "let it crash"** — process linking/monitoring,
  restart strategies. An RTL-level feature (Track B, once the process model
  exists), not a frontend-syntax problem.
- **Hot code reloading** — a hallmark BEAM feature; almost certainly out of
  scope for a v1 (no equivalent concept anywhere in PXX's static-link/ELF
  model) — flag as an explicit non-goal once this scoping starts, don't let it
  silently block everything else like `comptime` did for Zig.
- **Bit syntax / binaries** (`<<...>>>` pattern matching on binary data) —
  Erlang-specific, no direct PXX equivalent; likely a moderate, self-contained
  addition once bit-level pattern matching exists for the tagged-union work
  above.

## Explicit early non-goals (proposed — confirm when scoping starts)

- Not distributed Erlang (node-to-node clustering) — v1 targets a single OS
  process, same posture as PXX's other frontends.
- Not hot code reloading (see above).
- Not compiling arbitrary existing `.erl`/OTP codebases — hand-port a call
  surface if needed, same rule as C/Rust/Zig's non-goals.

## Acceptance (for this scoping ticket only)

A gap-map table (like [[feature-zig-frontend]]'s "AST/IR gap map") showing what
lowers onto existing IR for free vs. what needs new shared machinery, plus an
honest sizing of the scheduler gap specifically (the one part with no close
existing analogue) and a validated (not assumed) answer on whether refcounting
extends cleanly to Erlang terms or hits a real wall (closures/ETS lifetime,
refcount-traffic cost). No code required to close this ticket — only a scoping
doc, same bar as the original Rust/Zig umbrellas before work started.

## Log
- 2026-07-05 — filed per user decision to scope Erlang ahead of attempting Zig.
  Track A once picked up; not scheduled, not greenlit to build.
- 2026-07-05 — corrected rationale twice this session: (1) dropped the
  "determinism" framing (Zig's comptime risk is termination, not determinism;
  Erlang's actor model is itself the more nondeterministic runtime model of
  the two — see [[feature-zig-frontend]]); (2) corrected the GC gap sizing
  downward — refcounting (already built for strings/dynarrays) plausibly
  suffices since Erlang term data is acyclic by construction, so the scheduler,
  not per-process GC, is now the single open unknown.
