---
track: U
prio: 45
type: decide
blocked-by: []
summary: "No global rule can win: Pascal, Python and C each let a user definition beat a builtin SOMETIMES, and the answer differs per routine. Proposal (user's steer, 2026-08-13): classify each library routine as reserved / overrideable-builtin / ordinary-library, declared AT THE DECLARATION in the library rather than decided by a parser arm — one predicate replacing the four ad-hoc mechanisms in place today. Open questions: the marker's spelling, the default tier, and who may reach a shadowed routine."
---

# Classify library routines by how strongly they own their name

Superseded framing (2026-08-13, user): the earlier version of this ticket asked
which single resolution RULE should win — builtins first, units first, or fix
the overload merge. **None of them can.** In Pascal a user routine beats an
intrinsic sometimes; in Python a module-level `def` beats every builtin; in C a
user `strlen` is not only allowed but occasionally required. The answer is a
property OF THE ROUTINE, not of the language, and it has to respect what a
programmer coming from that language assumes. So the question becomes: how do
we say, per routine, how strongly it owns its name?

We control both sides of this — what goes in `compiler/builtin/**` is our
deliberate choice, and it does not have to live in the compiler at all; a
library unit is a legitimate home. That is what makes the classification
possible rather than a guess about someone else's runtime.

## The landscape, measured 2026-08-13

**Within NilPy** — `def <name>(x)` then call it, 17 intercepted builtins:

| result | names |
| --- | --- |
| user def wins — CPython's answer | len, sum, sorted, max, min, format, input, str, abs, round, enumerate, callable, repr |
| refused with a diagnostic | print (it LEXES to a token), zip, type |
| **silently ignored, builtin runs** | **open** — [[bug-nilpy-a-user-def-named-open-is-silently-ignored]] |

**Four different mechanisms** decide that question today: a lexer keyword
(`print`), `PyUserShadowsProc` (`enumerate`), a `FindSym(name) < 0` guard
(`input`, `type`), and a `ProcUnitIdx = -1` check (`format`). `open` has none.
Every new intercept re-decides it from scratch, which is why one of them is
wrong and why the next one will be too.

**Against Pascal units** — a later unit's routine declared without `overload`
hides an earlier one entirely (FPC-faithful, measured). sysutils' `Format` is
declared that way and is used after pylib, so a pylib `format` stopped existing
the moment a program said `import json`. Marking both `overload` does merge the
sets in pxx, but then an `array of const` literal fails to match —
[[bug-a-array-of-const-literal-does-not-match-in-a-cross-unit-overload-set]].
Collision surface today is small: of pylib's 22 Python-named free routines only
`min`/`max` also name an RTL free routine, and both are frontend-handled.

## The proposal

Three tiers, and **the tier is declared at the declaration** — in the library
source, next to the routine, the way `overload` is — not in a table inside the
parser:

1. **`reserved`** — the name is syntax. A user definition is REFUSED with a
   diagnostic naming the tier. Should be nearly empty; `print` is here today
   only because it lexes to a token, and arguably should not be.
2. **`builtin`** (overrideable) — the default for a language's builtins. The
   program's OWN definition (a `def`, an assignment, a class) shadows it; an
   imported unit's routine does NOT. This is CPython's actual scoping — builtins
   are the last scope searched, and an imported Pascal unit is not a Python
   scope at all — and it is what 13 of the 17 already do by accident.
3. **`library`** — no special status; ordinary resolution rules for the
   frontend's own language (uses order, overload sets, FPC shadowing). For
   routines that are not builtins of the accepting language.

The frontend then asks ONE predicate — "what tier does this name hold, and does
the program bind it itself?" — instead of each intercept inventing an answer.
That is the normalise-don't-special-case fix for the `open` bug rather than a
fifth mechanism, and it is per-FRONTEND by construction: the same pylib routine
can be `builtin` for `.npy` and `library` for a Pascal program that happens to
use the unit.

## What the user needs to decide

1. **The marker's spelling.** A Pascal-style directive on the declaration
   (`function len(l: TPyList): Integer; builtin;`) is local and greppable and
   needs a lexer/parser change; a registry unit listing name + tier + frontend
   is zero syntax change but splits the fact from the routine. Recommendation:
   the directive — the whole point is that the fact lives WITH the routine.
2. **The default tier for an unmarked routine.** `library` (conservative,
   nothing changes until marked) or `builtin` (matches what most already do,
   but silently changes resolution for every existing pylib export).
   Recommendation: `library`, and mark the builtins explicitly — a tier that is
   inherited by accident is the mess we are getting out of.
3. **Whether a shadowed routine stays reachable**, and how. Python has
   `builtins.len`; we have qualified names (`pylib.len`). Recommendation: yes,
   qualified — it costs nothing and makes shadowing recoverable.
4. **Whether `print` stays reserved.** CPython lets `def print` win. Making it
   overrideable means it stops being a token, which is a real lexer change for
   a shape almost nobody writes.

## Scope note

This ticket is the RULE. The two defects it uncovered are filed separately and
neither waits on it: the `open` one-liner and the cross-unit overload merge.
C and Zig get the same treatment when they need it — the tiers are per-frontend
by design — but nothing there is broken today, so this is N-first.

## Gate (whichever shape is chosen)

The 17-name shadowing sweep diffed against CPython (a `def` of each builtin
wins, or is refused by an explicit `reserved` diagnostic — no silent
ignores); `format(7.5, ".1f")` correct with and without `import json`;
`Format(fmt, [args])` still correct from Pascal; and one intercept deleted per
mechanism the predicate replaces, so the count of ways to answer this question
goes DOWN.
