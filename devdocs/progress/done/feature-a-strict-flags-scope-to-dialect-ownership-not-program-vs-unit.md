---
track: A
prio: 50
type: feature
summary: "Strict flags currently exempt code by `CurrentUnitIdx < 0` — main program vs ANY unit — so `--strict-fpc` polices the one file that isn't FPC's and exempts Synapse entirely. The right axis is OURS vs THEIRS: our RTL is written in the pxx dialect and no command-line flag should re-judge it, while external units and the user's own program should be policed. Unblocks folding --strict-overload into the umbrella."
status: done
owner: claude-A
---

# Strict flags should scope by dialect ownership, not by program-vs-unit

- **Type:** feature (compiler flag semantics) — **Track A** (`lexer.inc`,
  `symtab.inc`, the strict checks in `parser.inc`).
- Raised by the user 2026-08-14 while deciding
  [[decide-may-uses-math-cost-the-heap-and-exception-runtime]]:

> *"Our own RTL is ours. strict-fpc only applies to external code — like Synapse,
> or others. Our own libraries should always be excluded from such a compiler
> flag."*

## The axis is wrong today

```pascal
if StrictOverload and (FindProc(name) >= 0) and (CurrentUnitIdx < 0) then
```

`CurrentUnitIdx < 0` means "we are in the main program". So the rule exempts
**every unit** — ours *and* Synapse's — and polices only the file being compiled.

That is backwards for a parity flag. `--strict-fpc` exists to check that code
written for FPC behaves as FPC would; Synapse **is** that code, and it is exactly
what the current scoping skips. The flag is weaker than it looks.

## The rule that makes sense

| code | judged by strict flags? |
|---|---|
| our RTL / `builtin` / `lib/pcl` | **no** — written in the pxx dialect by design |
| external units (Synapse, fgl, fpjson) | **yes** — they are FPC code, so hold them to FPC's rules |
| the user's own program | **yes** — unchanged from today |

**The framing that makes this principled rather than a hack:** our RTL's dialect
is a *property of the RTL*, not a user-selectable mode. A command-line flag has
no business changing how already-written library code is judged. Once that is
said out loud, per-unit flag behaviour stops being an exception and becomes the
rule.

## Mechanism: a source directive, NOT a path predicate

The user's own framing — *"our own libraries have a sort of implicit `$mode
pxx`"* — is the better mechanism, and it beats the path rule I first proposed:

- it is **explicit and greppable**, in the file it describes;
- it **survives vendoring** — someone copying our RTL into their tree keeps the
  dialect marking, where a `lib/rtl/` path rule would silently reclassify it;
- it is the standard Pascal idiom: FPC has `{$MODE objfpc}` / `{$MODE delphi}`
  per unit for precisely this.

**Precedent already in the tree, and it is the exact inverse:** `{$MIMIC FPC}`
(`lexer.inc:1747`) pins FPC-compatibility *in the source* — *"so a project
carries its own compatibility need"*. `{$MODE PXX}` is the same idea pointed the
other way: this unit declares its dialect, so don't re-judge it by another's.

`{$MODE}` already exists as a hook (`lexer.inc:1735`) and currently only toggles
`DelphiMode`, with other modes "accepted but inert" — so there is a place to put
this without inventing syntax.

## The payoff

`--strict-overload` can then join the `--strict-fpc` umbrella. Its exclusion is
documented in `EnableStrictFpc` and the reason is exactly this:

> *"our own RTL uses undirectived overloads by design … requiring the `overload`
> directive would fail to compile every RTL-using program (fpjson/Synapse)"*

With ownership scoping, that objection disappears: our RTL is exempt because it
declares its dialect, and the user's code and external units get the rule.

## Two things to state up front rather than discover

1. **The main program stays policed.** "Exempt our own code" must not be misread
   as exempting the thing being compiled. It is *our RTL* that is exempt.
2. **A unit with no dialect marking defaults to policed.** Anything else makes
   the flag silently weaker as the tree grows, which is the failure this ticket
   is fixing.

## Related

- [[decide-may-uses-math-cost-the-heap-and-exception-runtime]] — where this came
  up; enrolling a costly flag in the umbrella is the decision that raised it.
- [[feature-p-defineglobal-a-define-that-crosses-unit-boundaries]] — the sibling
  idea from the same conversation.

## Gate

`--strict-overload` folded into `EnableStrictFpc`, and fpjson / Synapse / fgl
still compile — which is the exact corpus its exclusion note names. Plus a unit
marked `{$MODE PXX}` demonstrably exempt while an unmarked one beside it is not.

## Triage 2026-08-19 (Track D re-triage pass, pin v364)

**Genuine feature, still wanted, unchanged** — `compiler/parser.inc:32241` is
still literally

```pascal
if StrictOverload and (FindProc(name) >= 0) and (CurrentUnitIdx < 0) then
```

with the comment beneath it still explaining the program-vs-unit axis, so the
scoping this ticket calls backwards is intact.

**Prior art worth knowing before starting, found while measuring.** The
compiler already has an "ours vs theirs"-shaped predicate for a different
purpose: `NilPyUserCode` (`symtab.inc`), introduced because
`CurrentUnitIdx < 0` was *also* the wrong axis there — it meant "main program
only" where the intent was "NilPy user code, main program **or** an imported
`.py` module", and the mismatch segfaulted a bound-method field
(`compiler/parser.inc:6928-6936`). Same wrong axis, same shape of fix, already
landed once. Read that predicate before writing a second one; whether dialect
ownership can share it or needs its own is exactly the question to answer
first.

## Resolution 2026-08-21 (Track A)

Implemented as the ticket specifies: a source directive, one predicate, unmarked
code defaults to policed.

**Mechanism.**

- `{$MODE PXX}` in `lexer.inc`'s existing `mode` handler (the one that already
  accepted other modes inertly) calls `MarkUnitPxxDialect(CurrentUnitIdx)`.
- `symtab.inc` gains `UnitIsPxxDialect` / `MarkUnitPxxDialect` / **`DialectIsPxx`**.
  `DialectIsPxx` is the single predicate every strict check consults — deliberately
  ONE function rather than the condition copied per check, which is the lesson
  `NilPyUserCode`'s nine-copy history already taught in that file (the Triage note
  above asked whether the two predicates could share; the answer is no — that one
  means "NilPy user code", this one means "written in our dialect" — but its
  *shape* is exactly what was copied).
- The check at `pasparser_proc.inc:1279` moved from `(CurrentUnitIdx < 0)` to
  `not DialectIsPxx`.
- 144 library files declare the dialect: 8 `compiler/builtin/*.pas` plus 136
  `lib/rtl/**` + `lib/pcl/**`.

**Both "state up front" clauses honoured.** The main program stays policed — an
unmarked program is judged exactly as before. A unit with no marking is policed
too, which is the half the old axis got backwards. `{$MODE PXX}` in a *program*
is accepted as an explicit opt-out by whoever is compiling, which is a real
answer rather than a hole: they wrote the directive.

**Measured, not reasoned.** `pinned` compiles AND RUNS a unit with undirectived
overloads under `--strict-overload` — direct proof the old axis never reached
units at all. `pinned` also accepts `{$MODE PXX}` silently (inert), so the marked
library files stay buildable by the stable binary; that is what makes marking 136
Track B files safe to land from Track A.

Three Makefile assertions, because any two of them pass with a broken flag: a
`{$MODE PXX}` unit with undirectived overloads is exempt, an unmarked but
directive-clean unit still compiles (the flag must not reject conformant FPC
code), and an unmarked undirectived unit is **rejected**. Plus a fourth: with no
flag, that same rejected program builds and runs — the dialect stays lax by
default.

## How to finish the fold (deliberately NOT done here)

The ticket's Gate has two halves. The scoping half is done and asserted. The
other half — folding `--strict-overload` into `EnableStrictFpc` — is **not**
made, and the reason is evidence rather than design:

> `--strict-overload` folded into `EnableStrictFpc`, and fpjson / Synapse / fgl
> still compile — which is the exact corpus its exclusion note names.

fgl, Synapse and fpjson live in `external/`, which is **gitignored and fetched on
demand**, and is not present in this checkout. Enrolling a flag in `--strict-fpc`
is a promise that those corpora still build; making that promise without running
them would weaken the one claim the umbrella makes — precisely what the existing
comment warns about for `StrictOverloadWidth`. The original *objection* is gone
(the RTL is exempt now, and an RTL-using program does compile under the flag —
asserted above); only the verification is missing.

Recipe for whoever has the corpora:

1. fetch `external/` (fgl, Synapse, fpjson),
2. build each with `--strict-overload` against the current pin,
3. if any rejects, the failures are the real work — each is either an FPC-code
   overload we mis-diagnose (a bug) or genuinely undirectived FPC source (which
   would mean FPC itself does not require what the flag requires, i.e. the flag
   is wrong, not the corpus),
4. only if all three pass, move `StrictOverload := True` into `EnableStrictFpc`
   and rewrite the comment at `lexer.inc:601` (it now points here).

The comment in `EnableStrictFpc` was updated to say exactly this, so the next
reader is not told a reason that is no longer true.

## Follow-on

Only `StrictOverload` is rescoped. The other strict flags (`StrictCase`,
`StrictOperator`, `StrictVisibility`, `RequireForward`, `StrictShiftWidth`,
`StrictVariantChar`) do not test `CurrentUnitIdx` at all today — they apply
everywhere — so there was nothing to rescope, but the moment one of them wants an
ownership carve-out, `DialectIsPxx` is the predicate to call. Filed:
[[feature-a-audit-strict-flags-against-dialectispxx]].

## Log
- 2026-08-21 — resolved, commit 28bd01e11.
