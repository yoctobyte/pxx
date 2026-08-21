---
prio: 45  # auto
owner: agent-A
---

# Emission size — reachability-gated dead-code elimination (umbrella)

- **Type:** feature (codegen / optimization) — Track A
- **Status:** done
- **Opened:** 2026-06-30 (merge of feature-lazy-standard-unit-emission +
  chore-runtime-emission-size, found redundant in triage)
- **Relation:** the concrete passes here would be hosted by
  [[feature-optimization-levels]]'s pass framework (kept separate; cross-linked).

## Goal

Shrink emitted binaries by emitting only reachable code. Two overlapping fronts,
unified here:

1. **Routine-level DCE for `uses`-unit bodies** (was feature-lazy-standard-unit-
   emission): a `uses textfile`/`builtin` pulls in whole unit bodies even when only
   one routine is called. `hello.pas` still emits ~31.6 KB vs a ~29 KB reachable
   baseline. Emit a unit routine only if reached from the program entry.

2. **Finer runtime-support emission** (was chore-runtime-emission-size): the
   implicit runtime helpers (string/dynarray/managed/exception support) are emitted
   coarsely; gate each on actual use.

Both are the same mechanism: build a call/reachability graph from the entry point
and skip unreferenced routine bodies. Do it once, cover both fronts.

## Acceptance

`hello` (and other minimal programs) shrink measurably (toward the ~29 KB
baseline) with no behavior change; self-host byte-identical; `make test` + cross
green. Ideally lands as an `-O`-gated pass under [[feature-optimization-levels]].

## Notes
- Merged from two redundant tickets (2026-06-30 triage). History in git.

## Done — 2026-08-21 (`--dce`, and `-O3` implies it)

`hello` went from **60298 to 17380 bytes**; the ticket asked for "toward the
~29 KB baseline". Code: 58522B -> 15604B, 113 emitted routines -> 41 live.

| program | before | after | |
| --- | --- | --- | --- |
| hello | 60298 | 17380 | -72% |
| arrays | 103832 | 19268 | -82% |
| test_class_is_as | 107941 | 23704 | -79% |
| test_dynarray_copy_managed_elems | 109164 | 27313 | -75% |
| lib_classes_tthread | 358975 | 147233 | -59% |
| lib_httpjson | 1737321 | 717798 | -59% |

Both fronts, as the ticket predicted, turned out to be one mechanism — and it
is front 1's mechanism: the "implicit runtime helpers emitted coarsely" of
front 2 ARE unit routines, so a reachability walk over routine bodies drops
them by the same rule. What is left of hello outside a routine body is ~1000
bytes of entry stub and lazily emitted stubs; there is no coarse-grained
runtime blob left to gate.

### Not lazy emission — a post-pass

`BodyAddr := CodeLen` sits at the prologue: the compiler emits a body the moment
it parses it, so at the point where you would want to skip one, nothing yet
knows who calls it. Lazy emission means replaying parser state per routine per
frontend; compacting afterwards is one language-agnostic pass over tables that
already exist. `compiler/dce.inc`.

### The actual work was making the references enumerable

Moving a body invalidates every PC-relative reference that crosses the gap, and
a stale rel32 does not crash — it calls into the middle of whatever slid up into
the hole. So most of this change is not the pass:

- **`EmitCallProc` now records EVERY internal direct call**, not only the forward
  ones. The old rule — record it when the callee's address is not yet known,
  otherwise write the displacement and forget — is exactly right until a body
  between caller and callee disappears. `CallFix` is now both the call graph the
  pass walks and the complete set of sites it re-patches. Proven inert by the
  self-host fixedpoint staying byte-identical.
- **`IREmitCodeCall` and the entry jump record a `CodeRef`** — the references
  that name a code OFFSET rather than a proc (the ~50 runtime stubs).
- Everything else PC-relative is **intra-body** (IR labels, loop/goto fixups,
  exception landing pads, inline-asm locals) and a body moves as a unit.
- `@proc` (ProcAddrFix) and VMT/RTTI slots (MethodFixups) are absolute and
  resolved from `BodyAddr` at write time — and both are **roots**, since an
  address that is taken can be called from anywhere.

**A range holding a CodeRef target is never dropped**, whoever emitted it. That
rule is what keeps the pass honest against a stub kind nobody listed: an
unreferenced stub costs its bytes, a wrongly dropped one costs a jump into
hyperspace.

### Refuses rather than guesses

Two bodies sharing a start address (the C frontend aliases one), a body that
never recorded its end, `-c` / `--shared` (their writers carry their own
code-offset tables), `-g`, a non-x86-64 target, a non-Pascal frontend.
`--dce-report` prints which.

### Evidence

- A compiler built **with** `--dce` — 284 bodies and 129 KB dropped, every
  reference in an 8.8 MB image relocated — compiles `compiler.pas` to a
  byte-identical binary. That one test exercises classes, generics, exceptions,
  managed strings, dynamic arrays, `@proc`, VMTs and file I/O at once.
- 22 programs run before/after with identical stdout+stderr+exit.
- `-O0` vs `-O3` (what optdiff does) identical on 9 of them.

`-O3` enables it, per the convention that a new pass lands in the free tier
first. That also buys the breadth the pass cannot buy itself: `tools/optdiff.sh`
sweeps ~900 programs demanding identical behaviour at -O0/-O2/-O3, so Track T's
opt tier is now a whole-corpus `--dce` differential.

### What is deliberately left

- **An unreferenced class keeps every one of its methods** — its VMT is emitted,
  and a VMT slot is a root. `hello` still carries `TInterfacedObject`'s four
  methods, `PXXTIOGetInterface`, `PXXIntfIMTOf`, `PXXVarClear` and
  `PXXVarStrAppend` for exactly this reason: a hello-world uses neither
  interfaces nor variants. That is data-side reachability (drop the unreachable
  RTTI blob, and the method roots go with it) and is filed separately as
  [[feature-a-unreferenced-class-rtti-keeps-every-method-alive]].
- Other frontends and targets: the pass refuses them, it does not miscompile
  them. Each is a matter of enumerating that frontend's own "call main" patch
  and that target's reference encodings.
- Default-on: not until the corpus evidence is the full matrix's, not mine.

## Log
- 2026-08-21 — resolved, commit e47988d52.
