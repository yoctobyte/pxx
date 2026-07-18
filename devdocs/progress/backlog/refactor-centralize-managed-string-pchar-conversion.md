---
summary: "Populate pointer-element-type metadata consistently (additive, fallback-preserving) — kill the recurring silent PChar/WideChar-conversion class at its source"
type: refactor
prio: 45
---

# Populate pointer-element metadata consistently — the low-risk fix for the conversion class

- **Type:** refactor / data-completeness (Track A — `parser.inc` registration + node
  creation, `ir.inc` predicates). **Additive and fallback-preserving — NOT a big-bang
  rewrite.**
- **Status:** backlog
- **Opened:** 2026-07-17, from a user observation ("we keep special-casing AnsiString,
  keep finding issues"). **Re-scoped 2026-07-18** after the user correctly pointed out the
  sane, low-risk shape: *just store the pointer type; C already does it.*

## The observation, and the corrected diagnosis

The recurring PChar/WideChar→string bugs are **one root**, and it is NOT "shape
enumeration is inherently wrong" — it is **"the element-type metadata is not populated in
every creation path."**

- The reader predicates (`IsNodePChar`, `NodeIsWideCharVal`) key on stored data — e.g.
  `ProcRetPtrElemTk[procIdx]` (a proc's return pointer-element type). That field already
  exists.
- The bugs were **registration paths that forgot to set it**: the external-directive path
  and the `$proctype` signature path each re-implemented registration and dropped the
  return-element fields, so the predicate read `tyUnknown` and skipped the conversion →
  silent garbage / segfault.

C proves the pattern is fine: `cparser.inc` has the *same* shape-walk
(`CNodePtrElemRec`), but at node creation (`cparser.inc:374`) it **computes once and
STORES** the element type on the node (`ASTSOffset` side-channel), so downstream reads are
a clean lookup. Mirror that.

## Instances (all the SAME pattern; the point-fixes are slices of this)

- [[bug-pascal-ansistring-cast-of-cdecl-call-result]] — external decl dropped
  `ProcRetPtrElemTk` (FIXED, `33f0d555`).
- [[bug-pascal-ansistring-cast-of-fnptr-call-result]] — `$proctype` sig dropped it +
  `IsNodePChar` missed `AN_CALL_IND` (FIXED, `9118a760`).
- [[bug-pascal-widechar-var-to-string-segfault]] / [[bug-pascal-widechar-var-to-string-other-contexts]]
  — `NodeIsWideCharVal` cast-only, missed the tyUInt16 var shape (assign + concat FIXED,
  `19fbf64a`/`6ea2e6ff`; arg residual open).
- The copy-pasted conversion block → one `WrapPCharToString` builder (`7e4bebc0`).
- **Not-yet-fixed dropped-field sites:** `parser.inc` `18447`/`19128`/`19649` — method-decl
  registrations that set `BodyAddr` + params but never `ProcRetPtrElemTk`. Harmless when a
  method has a body (the impl re-registers via the normal path), but a decl-only PChar
  method (abstract/interface/virtual-via-base) would mis-lower `AnsiString(ref.Method())`.

## Status after the reachable-instance audit (2026-07-18)

**The reachable instances are all FIXED** (the 5 point-fixes above were the slices).
Verified: instance-method AND class-method PChar-result casts (`AnsiString(o.GetP())`,
`AnsiString(TObj.GetPC())`) work — a method **with a body** resolves to the impl's
procIdx, which the normal registration path populates. So the 3 method-decl sites
(`18447`/`19128`/`19649`) are **defensive-only and NOT reachable by a normal call** — no
failing test is constructible. Deliberately **not** patched: adding metadata there would
be self-host-identical with no test, and would set a shared field from a possibly-stale
`LastTypePointerElemTk` that cannot be verified — which violates the "added data must be
correct" rule. Leave them until a real reachable case appears.

Net: **do-with-a-test-when-needed.** This ticket is now forward insurance + documentation
of the pattern, not a list of open bugs. The bleeding is closed.

## The plan — additive, fallback-preserving, incremental (LOW RISK)

The whole reason this is safe: **add a stored fast-path, keep the old shape-walk as a
fallback.** A reader that consults stored metadata first and falls back to the existing
enumeration can only ever *add* recognitions (fix a missed shape) — never remove one. It
is impossible to regress by construction.

1. **Finish the proc side (first slice, do now).** Set `ProcRetPtrElemTk` (+ the other
   return-element fields) at the 3 method-decl registration sites so *every* proc
   registration records it — matching the external/`$proctype` fixes already landed.
   Purely additive; self-host byte-identical unless it fixes a real case.
2. **Node side (later).** Store the pointer-element type on pointer-typed nodes at
   creation (C's store-on-node pattern); have `IsNodePChar` read the stored value first,
   fall back to the shape-walk if unset. Populate creation sites incrementally.
3. **Fold WideChar in.** Same treatment (WideChar==tyUInt16 has no marker; the safe
   contexts are already handled — see [[project_string_conversion_shape_blindspot_pattern]]).

Each step: self-host byte-identical + a targeted regression + a fuzz pass. No step is a
sweep of all 688 `tyString` branches — that count is just the *evidence* of the sprawl,
not a to-do list.

## Why not just keep point-fixing?

You can, and it's safe — each new shape found by fuzzing gets a one-line populate. This
ticket is the *systematic* version: audit the creation sites once so future shapes are
covered as the data is populated, instead of waiting for a fuzzer to draw blood on each.
Do it at the pace that suits; the bleeding is already stopped.

## Acceptance

- Every proc-registration path sets `ProcRetPtrElemTk` (grep audit); a decl-only PChar
  method cast works.
- `IsNodePChar` prefers stored metadata with the shape-walk as fallback (additive).
- The known instances stay fixed; a fuzz pass finds no new PChar/WideChar-conversion
  divergence.
- Gate: `make test` + self-host byte-identical per slice.

## Explicitly NOT

- **Not** a big-bang rewrite of the conversion sites or the 688 `tyString` branches.
- **Not** removing the shape-enumeration walks — they stay as the fallback.
- **Not** reworking the managed-string runtime/ABI — this is about *where the compiler
  records/reads the pointer element type*, nothing about how strings are represented.
