---
track: A
prio: 50
type: feature
summary: "Strict flags currently exempt code by `CurrentUnitIdx < 0` — main program vs ANY unit — so `--strict-fpc` polices the one file that isn't FPC's and exempts Synapse entirely. The right axis is OURS vs THEIRS: our RTL is written in the pxx dialect and no command-line flag should re-judge it, while external units and the user's own program should be policed. Unblocks folding --strict-overload into the umbrella."
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
