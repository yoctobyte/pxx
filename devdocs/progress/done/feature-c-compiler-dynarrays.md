---
prio: 60
---

# Compiler: port fixed-size in-RAM tables to dynarrays / source-size allocation

- **Type:** feature (compiler infrastructure) — **Track A** (core: `defs.inc` globals + the
  code that indexes them).
- **Status:** done
  we are (by design) an all-in-RAM compiler, and real-world corpora are now large enough
  to sit near the fixed ceilings.

## Why now
pxx holds the whole translation unit in RAM in fixed-size global arrays sized by
compile-time constants (`defs.inc`). That is a deliberate design (all-in-RAM, no streaming),
but the sizes are hard-coded and over-provisioned "big enough" guesses. Two costs:

1. **Silent corruption on overflow.** Several of these arrays were (or are) written without
   a bounds check, so exceeding the constant scribbles into the adjacent global instead of
   erroring. duktape exposed one: `TokChars` (the C token string pool) had **no** bounds
   check at its two write sites (`CLexAll`, `CLexAppend`) — a large-enough source would
   silently corrupt `Tokens[]` and mis-tag tokens. (Guards added in commit 9aef018d as a
   stopgap; duktape itself only used 0.7 MB of the 8 MB pool, so this wasn't the actual
   duktape blocker — that was a preprocessor bug — but it is a real latent overflow.)
2. **Wasted RAM + arbitrary ceilings.** `MAX_TOKENS = 2097152`, `STRING_CAP = 8 MB`,
   `MAX_CPREP_CHARS = 8 MB`, `MAX_CPREP_MACROS = 32768`, `MAX_CPREP_PARAMS`, the 33-slot
   `CPTempStr*` / `CPExpandedArg*` ladders, etc. The bss is ~318 MB largely from these
   (`Tokens[]` + parallel `TokPackRecords`/`CAttrFlags`/`CAttrAlignValues` at 2 M each).
   A source that needs one table bigger than its constant fails even if total memory is
   fine; meanwhile every small compile pays the full 318 MB.

## The two fixes (quick vs ultimate)
- **Quick (per-array, as needed):** bump the specific constant that a real corpus hits, and
  make sure every write site bounds-checks and `Error`s cleanly (never silently overflows).
  Cheap, but grows bss for everyone and just moves the ceiling.
- **Ultimate (this ticket):** port the fixed arrays to **dynamic arrays** (`SetLength`,
  geometric growth) sized to the actual source — no compile-time ceiling, RAM proportional
  to input. `CPrepOut` already does exactly this (geometric-growth AnsiString, trimmed to
  live length — see `cpreproc.inc` header comment); generalise that pattern to `Tokens[]`
  and friends, the `CPrep*` pools, and the `CPMValueOff`/name/param tables.

## Scope / sequencing (big, do incrementally)
- Start with the **token tables** (`Tokens`, `TokChars`, and the parallel per-token arrays)
  — biggest bss, clearest win, and the arrays a large TU hits first.
- Then the **preprocessor pools** (`CPrepChars`, `CPMValueOff`/`CPMNameOff`/…, `CPrepOut`
  is already dynamic).
- The 33-entry `CPTempStr*` / `CPExpandedArg*` and `CPActiveMacros[0..63]` ladders are a
  different shape (macro-expansion depth) — bound-check + enlarge, or restructure to a
  growable stack; lower priority (duktape never exceeded 64 active).
- **Gate:** self-host byte-identical after each conversion (the compiler builds itself, so
  its own token/preproc volume must still round-trip), `make test`, `--tier full` for the
  matrix. Convert one table per commit; keep each landing green.
- Landmine: `SetLength` with no spare capacity is O(n²) for per-element appends — use
  geometric growth (see [[project_pxx_setlength_no_spare_capacity_append_quadratic]] and
  `CPrepOut`).

[[feature-c-corpus-duktape]] · [[feature-c-corpus-expansion]]

## 2026-07-14 — MERGED with [[feature-dynamic-compiler-tables]]; RESCOPED to the master-safe half

These two tickets are the same work filed twice (2026-06-27 and 2026-07-09). The
OLDER one is the canonical dynarray-port ticket and carries explicit user
constraints this one must not override: **the overhaul happens on a dedicated dev
branch, not master, and is explicitly LATER** (user decision 2026-06-27 — static
arrays accepted for now). Do not start the port on master from this ticket.

What remains HERE (master-safe, small, the "quick" half above): **audit the big
fixed pools' write sites and make every one bounds-check and Error cleanly** —
silent adjacent-global corruption is a bug class, independent of the port.
TokChars got stopgap guards at its two CLex sites (9aef018d); the remaining ~38
TokChars write sites across 21 lexers/parsers, LoadFileBuf, and the other 8 MB
pools have not been audited.

## Log
- 2026-07-14 — resolved, commit e516f0bf.
