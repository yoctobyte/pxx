# Experiment: compile FPC's own source as a pxx stress probe

- **Type:** experiment / open-ended probe (NOT a completion goal)
- **Status:** rainy-day — pick up when curious about pxx's real ceiling
- **Owner:** Track A (compiler) — needs the RTL-shadow / define-profile mechanism
- **Opened:** 2026-07-05
- **Relates:** [[project_fgl_works_fpc_compat_batches]] (the milestone that
  prompted this), [[feature-fpc-vs-pxx-feature-boundary]] (the *inverse* — our
  compiler's FPC∩PXX subset; this ticket is about *their* code), the synapse
  per-library-defines ticket (the config mechanism to reuse)

## Context — the milestone that raised the question

2026-07-05: pxx compiles **real, unmodified FPC 3.2.2 `fgl.pp`** under
`--mimic-fpc` and the result **runs correctly** — `TFPGList<Integer>`
(Add/IndexOf/Insert/Delete/Sort-with-callback/for-in enumerator) and
`TFPGMap<Integer,Integer>`. That is a genuine maturity signal for the
compiler front/backend: generics, method overloads, method pointers,
properties, and a big real-world unit all work on someone else's Pascal.

**But "compile fgl" ≠ "compile FPC".** fgl is a *library*. It compiles because
`--mimic-fpc` makes FPC source resolve `uses types, sysutils, classes` to
**pxx's** RTL — pxx substitutes its own runtime, and fgl only needs container
*semantics*, which pxx's RTL provides. Only units pxx does not ship (fgl,
contnrs, …) come from the FPC tree.

## The two paths, and why this is parked (not chased)

**Path A — keep grinding fcl-base units (contnrs, custapp, inifiles, …).**
Every wall is a *missing function/class in pxx's `lib/rtl`* (`TFPList`,
`StdOut`, `GetEnvironmentVariableCount`, …). Pure Track-B library accretion.
fcl-base is dozens of units, each its own surface. **This is an asymptote, not
a finish line** — you can add surface for weeks and never reach "compile FPC."
Low intellectual signal: the hard *compiler* constructs are already proven.
(If someone does want to knock a couple down: `TFPList`/`TFPObjectList` in
`lib/rtl/classes.pas` unlocks contnrs **and** inifiles together.)

**Path B — compile FPC's *compiler* (`compiler/pp.pas`, `cutils`, `cclasses`).**
Genuinely harder and more *interesting* — it stresses pxx differently. Probed
2026-07-05, first wall in ~5 minutes:

- `cutils` / `cclasses` wall at `{$asmMode default}` (cutils.pas:26) —
  **trivial parser fix** (accept the directive value instead of erroring;
  pxx only accepts `intel` today).
- Behind it: `{$i fpcdefs.inc}` — FPC's compiler is **parameterised by
  build-time CPU defines** (`-dx86_64`, `-dGENERIC_CPU`, …). It is not
  standalone source; it is source **+ a build-config define profile**. So a
  probe needs an FPC-compiler define profile, exactly the per-library
  fine-grained-defines mechanism (synapse pattern) applied to FPC.
- `cclasses.pas` = FPC's **own** container/string classes (TFPHashList,
  ansistring internals). **Here the shadow model that made fgl work breaks**:
  FPC's *compiler* is deeply coupled to FPC's *exact* System/RTL internals,
  unlike fgl which only needs container semantics. This is the real
  "what's ours / what's theirs" boundary decision — either shadow even more of
  the RTL, or actually compile FPC's cclasses against FPC's system unit (a
  much bigger commitment).

## Why probe, not complete

The value of Path B is **not** finishing it — it is **reading the first 3–4
walls to learn what kind of gap they are**:

- **compiler-capability gaps** (a construct pxx can't parse/lower) → *interesting,
  worth fixing, tells us pxx's real ceiling*; or
- **RTL-coupling gaps** (FPC wants its own System guts) → *a boundary decision,
  not a bug — how much of FPC's runtime do we shadow vs compile?*

The fcl-base grind (Path A) surfaces **only** library gaps and teaches nothing
new about the compiler. Path B is the informative experiment.

## Concrete first steps when picked up

1. Accept `{$asmMode <anything>}` (parse-and-ignore non-`intel` values) — one
   lexer/directive edit. Unblocks the very first token of every compiler unit.
2. Stand up an FPC-compiler **define profile** (`--mimic-fpc-compiler`, or a
   defines file consumed like the per-library config) supplying `x86_64` +
   the `fpcdefs.inc` gates. Reuse the synapse per-library-defines machinery.
3. Point at `cutils` first (lowest-level, fewest deps), then `cclasses`.
   Record each wall and classify it capability-gap vs RTL-coupling.
4. Stop after ~4 walls and decide: rabbit hole, or a real target worth a
   dedicated push.

## Explicitly deferred / undecided

- Whether "compile FPC" ever becomes a real goal, or stays a probe.
- Where the ours/theirs RTL boundary sits for the *compiler* (fgl answered it
  for *libraries*: shadow pxx's RTL; the compiler may need a different answer).
- The literal Stop-hook goal "continue until we can compile FPC" is ambiguous —
  fcl-base grind never reaches it; compiler-probe aligns with it but is
  open-ended. That ambiguity is a scope call for the user, recorded here so it
  is not rediscovered cold.

## Acceptance (of the *experiment*, not of "FPC compiles")

A short write-up: the first 3–4 FPC-compiler-source walls, each classified
capability-gap vs RTL-coupling, and a recommendation on whether Path B is worth
a dedicated push. No code must ship for this ticket to be "done" — the
deliverable is the *signal*.
