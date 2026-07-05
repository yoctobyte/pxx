# Erlang frontend — scoping only

- **Type:** feature — scoping ticket (Track A, once picked up)
- **Status:** backlog — scoping only, no code, not greenlit
- **Owner:** —
- **Opened:** 2026-07-05 (user decision — prioritized ahead of [[feature-zig-frontend]] (parked))
- **Priority:** unranked

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
spread across the *runtime*: a preemptive, fair, reduction-counted scheduler
for potentially millions of lightweight processes, **per-process isolated
heaps with independent garbage collection** (PXX today only has string
refcounting, not a tracing/generational GC — Erlang needs the latter, per
process), and copying message-passing between those isolated heaps. That is
not "syntax sugar and hashing" — the syntax (pattern matching, immutability,
tuples/atoms/maps) is the easy part, same as Zig's type theory was the easy
part of Zig. **The hard part — a real preemptive scheduler + per-process GC —
is arguably a bigger, more novel runtime-engineering lift than Zig's comptime
interpreter, not a smaller one.** It's a different kind of hard, not an easier
one. Worth scoping specifically *because* it's a different domain (proves out
runtime/scheduler architecture this project doesn't have yet, useful beyond
Erlang), not because it's a shortcut.

**This ticket is scoping only** — same posture as the original Rust/Zig
umbrellas before any code: map Erlang's constructs onto existing/needed IR,
identify what's free vs. what needs new shared machinery (especially: how far
is PXX today from *any* form of tracing GC, since Erlang's process-isolated
heaps need one), before committing to a build.

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
- **Per-process isolated heap + garbage collection** — the part most likely to
  be underestimated. BEAM processes each get their own heap, collected
  independently (no stop-the-world pause across the whole system), with
  messages *copied* between heaps on send (shared-nothing). PXX's memory model
  today is refcounted managed strings, not a tracing/generational collector —
  there is no existing GC to extend here, this is new from scratch. Size this
  gap explicitly before estimating anything else; it is plausibly the single
  largest item in this whole ticket, bigger than the scheduler itself.
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
honest sizing of the scheduler gap **and** the per-process GC gap specifically
(the two parts with no close existing analogue — do not let syntax-level
familiarity understate either). No code required to close this ticket — only a
scoping doc, same bar as the original Rust/Zig umbrellas before work started.

## Log
- 2026-07-05 — filed per user decision to scope Erlang ahead of attempting Zig,
  given Zig's comptime-determinism conflict with the fixedpoint self-host gate.
  Track A once picked up; not scheduled, not greenlit to build.
