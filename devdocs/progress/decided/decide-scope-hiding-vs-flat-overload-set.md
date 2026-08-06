---
track: U
prio: 60
status: resolved
resolved: 2026-08-06
type: decision
summary: "One rule explains four separate symptoms: a declaration should HIDE a same-named one from an outer/earlier scope unless marked `overload`. pxx behaves as if everything were `overload` — one flat set, first-in-chain wins. Decide whether to adopt hiding, and which marker carries it: any {$mode}, --strict-overload/{$MIMIC FPC}, or the default"
---

# Decide: does a declaration hide an outer/earlier same-named one, or join one flat set?

- **Type:** decision — Track U. **Consolidates three tickets** that turned out
  to be facets of one rule.
- **Opened:** 2026-08-05, reframed with the user 2026-08-06.
- **Supersedes:** `decide-inner-declaration-hides-or-competes-with-outer-overloads`
  (same file, retitled — "inner declaration" read as *nesting*, and nesting is
  the one case that already works).
- **Absorbs as a facet:** [[bug-p-uses-order-does-not-decide-which-unit-wins]].
- **Partially fixed already:** [[bug-p-program-function-does-not-shadow-used-unit]].

## The rule

> A declaration **hides** a same-named one from an outer or earlier scope —
> unless it is marked `overload`, which merges them into one set.

That is standard Pascal scoping, not an FPC quirk. **pxx behaves as if
everything were marked `overload`**: one flat set across all scopes, resolved by
argument fit, with registration order as the tiebreak. That single difference
produces every symptom below.

## Four symptoms, one cause — measured

| case | FPC | pxx |
| --- | --- | --- |
| nested routine hides outer | hides | ✅ — but **by accident** |
| program declaration hides used unit | hides | ⚠️ partial — only when arg types match EXACTLY |
| later `uses` hides earlier | hides | ❌ takes the first |
| `overload` merges the sets | merges | ✅ (because pxx always merges) |

### Why nested already works — and why it does not generalise

```
nested:         IntToStr$9      <- mangled, so it never competes
program-level:  IntToStr        <- same symbol as sysutils'
```

A nested routine is lifted with a mangled name, so inside its enclosing routine
there is no contest: sysutils' `IntToStr` is a *different symbol*, not a losing
candidate. The mechanism is unavailable at program/unit level, where the routine
is exported under its real name. So "make it work like nested does" is not a
shortcut.

### The partial fix, and exactly what it left

```pascal
program n2; uses sysutils;
function IntToStr(v: Int64): AnsiString; begin IntToStr := 'program'; end;
var a: Int64;
begin
  a := 5;
  writeln(IntToStr(a));   { pxx: program   FPC: program }   <- fixed (a4962e2a7)
  writeln(IntToStr(5));   { pxx: 5         FPC: program }   <- the open case
end.
```

`a` is `Int64`, so both candidates match exactly and scope breaks the tie —
that is what the fix added. `5` is `tyInteger`, so the exact-match phase misses
*both*, and the later phases rank by fit, where sysutils' is equally
convertible. FPC never reaches that comparison because your declaration removed
sysutils' from the candidate set.

### `overload` already behaves correctly

```pascal
function IntToStr(const t: AnsiString): AnsiString; overload;
  IntToStr('x')        -> mine    (both)
  IntToStr(Int64(5))   -> 5       (both — the unit's stays reachable)
```

So the escape hatch works today; it is the *default* that differs.

## Implementation note — this is candidate REMOVAL, not ranking

Recorded because the obvious reading cost a night. Implementing "latest wins" as
**ranking inside the flat chain** broke two things that `gate.sh quick` passed:
the compiler could not compile itself (`set item must be one character` at
`EmitAsmX64([...])`), and the NilPy stdlib segfaulted at `sum(range(i))`. Root
cause: `FindProc` returns a **representative** of a same-named set, and the
parser reads its *signature* to decide how to parse a call while `pyparser`
reads its *RetType* to infer expression types.

The hiding formulation is different, and probably **less** invasive:

- `EmitAsmX64`'s two overloads are in the **same scope**, and same-scope
  declarations do not hide each other — they are overloads. Under hiding both
  stay in the set and signature resolution picks correctly. That break was an
  artifact of the wrong formulation, not of the rule.
- **NilPy is the genuinely unmeasured risk.** Hiding could still change which
  procs are candidates across the `pylib` / `pyeval` / `builtin` scopes, and
  that is exactly where the segfault came from. Measure before believing any
  estimate.

Any change here needs `--tier limited` at minimum; the quick tier passed both
broken versions.

## The second question: which marker carries it?

Measured in-tree, `{$mode ...}` occurrences:

    112  {$mode objfpc}      31  {$mode delphi}      2  {$mode fpc}

    by tree:  test 111 · lib 7 · compiler 5 · examples 1

1. **Any `{$mode ...}`.** `{$mode}` is a reliable marker that *this file was
   written for FPC*, which is precisely the signal wanted — and it lands
   automatically on vendored real-world code, serving compile-real-world-as-is
   directly. The directive already exists and already carries one behavioural
   delta (`DelphiMode`, the @-optional procedural value), so this extends a
   mechanism rather than inventing one. **Blast radius ~145 files including 5
   compiler files, so self-host is in scope.**
2. **`{$MIMIC FPC}` / `--strict-fpc` / `--strict-overload`.** The existing
   "opt into FPC behaviour, never default" vehicle. Zero surprise. But
   vendored FPC source does not carry it, so the mission case gains nothing.
3. **Default everywhere.** Defensible precisely because hiding is *standard
   Pascal*, not an FPC dialect choice: pxx's flat set is an artifact of
   first-in-chain winning, not a lax-dialect decision anyone made. That makes
   it arguably more bug than dialect. Largest blast radius.

**Not** `{$mode fpc}` specifically: in real FPC that is one of four dialect
selections and the least used (2 files here), while the hiding rule holds in
*all* modes — so scoping to it would still be wrong for the 112 objfpc files,
and would overload a directive that means "base-dialect FPC source", not
"be strict with me".

## Recommendation

**Option 1** — any `{$mode}` carries it, with `--strict-overload` as the
whole-program override. Strongest form of the source-level idea and it serves
the north star directly.

Two conditions before committing:

- sweep the ~145 files first; the **5 compiler files decide the sequencing on
  their own** — if honoring `{$mode}` changes self-host, that is the gate;
- keep `{$mode}` and `--strict-overload` meaning *exactly* the same thing, one
  file-scoped and one program-scoped. Do not let `{$mode}` become a second
  strictness axis that drifts from `--strict-*`.

## Gate (whichever option)

`IntToStr(5)` reaches the program's declaration; `uses a, b` binds b's and
`uses b, a` binds a's; `overload` still merges; nested unchanged; NilPy suite
and self-host both green under `--tier limited`.


## DECIDED 2026-08-06 — option 3: hiding becomes the DEFAULT, everywhere

**User's call**, and the stronger of the options on the table — not the
`{$mode}`-gated one recommended above.

The reasoning that carries it is the one that made option 3 worth listing at
all: **hiding is standard Pascal, not an FPC dialect quirk.** pxx's flat
overload set is not a lax-dialect decision anybody made — it is an artifact of
first-in-chain winning in `FindProc`. That makes it closer to a bug than a
dialect, and a bug does not belong behind a compatibility flag.

It also avoids the trap flagged in the recommendation: no second strictness
axis. There is one rule, it is the Pascal rule, and `{$mode}` stays what it is
today (one behavioural delta, `DelphiMode`).

### What this means concretely

- an unqualified call prefers a declaration in the **current scope**; failing
  that, the **latest declaring scope**;
- a hidden declaration is **removed from the candidate set**, not merely ranked
  below — so `IntToStr(5)` converts for the program's `Int64` version instead
  of finding sysutils' equally-convertible one;
- same-scope declarations do **not** hide each other; they are overloads and
  resolve by signature as today. `overload` keeps its current meaning as the
  explicit cross-scope merge;
- `--strict-overload` and `{$MIMIC FPC}` are **not** involved. Nothing new is
  gated.

### Non-negotiable preconditions, both already measured once

1. **Removal, not ranking.** Ranking inside `FindProc`'s chain broke the
   self-compile (`EmitAsmX64([...])` parsed as a set, because the parser reads
   the returned representative's *signature*) and segfaulted the NilPy stdlib at
   `sum(range(i))` (because `pyparser` reads its *RetType*). Both passed
   `gate.sh quick`.
2. **NilPy is unmeasured and must be measured first.** Hiding can still change
   which procs are candidates across the `pylib` / `pyeval` / `builtin` scopes.
   `--tier limited` at minimum; the quick tier is not evidence here.

### Implementation

[[bug-p-uses-order-does-not-decide-which-unit-wins]] is unblocked and becomes
the implementation vehicle — it now covers both remaining facets (uses-order and
the convertible-argument case), since one rule fixes both.
