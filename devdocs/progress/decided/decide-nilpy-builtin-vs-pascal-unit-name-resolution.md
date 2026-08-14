---
track: U
prio: 45
type: decide
blocked-by: []
summary: "Settled by the governing rule (user, 2026-08-13): the DEFAULT follows the reference implementation per frontend — CPython for .npy, FPC for .pas — deviations behind --strict-*. So shadowing is ALLOWED and PREFERRED, `reserved` needs the bar 'principally unsolvable', and the tier is a compatibility statement rather than a convenience. What is left to decide: the marker's spelling, whether `print` stops being a token, and whether a --strict-python peer is wanted."
status: decided
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

## The governing rule (user, 2026-08-13) — and what it settles

> "We try to stay compatible. If FPC behaves this way, we follow. CPython, we
> follow. Exceptions are there to be — hence `--strict-fpc`, and maybe we need a
> `--strict-python`. In general shadowing is allowed, and preferred, unless.
> Approach this from PHILOSOPHY, not from quick hacks or what is easiest.
> Correctness first, unless principally unsolvable."

This is not a tie-breaker among the three options above — it decides the shape
of the tier table itself, and it overturns two of the recommendations this
ticket carried an hour earlier:

- **The default tier is `builtin` (overrideable), not `library`.** The earlier
  recommendation ("default to `library`, mark builtins explicitly") was
  conservatism about OUR migration risk, which is exactly the kind of reasoning
  the rule rejects. CPython lets a module-level `def` shadow every builtin, so
  that is the default and an unmarked routine gets it.
- **`reserved` needs a much higher bar: principally unsolvable.** Not "the
  intercept claimed the call first", not "it lexes to a token" — a real grammar
  impossibility. On that bar `print` does NOT qualify: `def print` is legal
  Python, so today's refusal is a quick hack (it lexes to `tkwriteln`) and the
  tier table is where that becomes visible instead of being lost in the lexer.
- **A shadowed routine must stay reachable**, because CPython has `builtins.len`.
  Following the reference means following it here too, not only where it is
  convenient.
- **The tier is a COMPATIBILITY STATEMENT, not a convenience knob.** Each entry
  says "the reference does X, so we do X" — or, where we deviate, names the
  `--strict-*` flag under which the reference's behaviour is restored. A tier
  chosen because it is easier to implement is a bug in the table.

Recorded as [[feedback_reference_compat_is_the_default_shadowing_allowed]].

## What the user needs to decide

1. **The marker's spelling.** A Pascal-style directive on the declaration
   (`function len(l: TPyList): Integer; builtin;`) is local and greppable and
   needs a lexer/parser change; a registry unit listing name + tier + frontend
   is zero syntax change but splits the fact from the routine. Recommendation:
   the directive — the whole point is that the fact lives WITH the routine.
2. **Whether `print` stops being a token.** The rule says it must — `def
   print` is legal Python and today's refusal is an implementation accident.
   The cost is real: `print` lexes to `tkwriteln`, so this is a lexer change
   plus every parser arm that keys on the token. Worth confirming you want it
   paid for a shape almost nobody writes, or explicitly deferred with the tier
   table recording `print` as a KNOWN deviation rather than a decision.
3. **Whether a `--strict-python` peer is wanted at all, and for what.** The
   shadowing question needs no flag — the reference ALLOWS it, so the default
   allows it and there is nothing to be strict about. A `--strict-python` would
   be for the other direction: refusing what CPython refuses, where NilPy is
   deliberately laxer (a mutated tuple, the divergences page). That is a
   separate campaign; the only question here is whether to reserve the name now.

Settled by the rule, no longer open: the default tier is `builtin`
(overrideable); `reserved` requires "principally unsolvable"; a shadowed
routine stays reachable under a qualified name.

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

## CLOSED 2026-08-14 — the three remainders fall out of rules decided the same day

> *"This is all like one big umbrella ticket, how we deal with the cross-language
> unit import."*

The **resolution rule** half was already settled by the 2026-08-13 governing
rule (default follows the reference implementation per frontend — CPython for
`.npy`, FPC for `.pas`). The three items left were narrower, and two of them are
now answered by principles established while clearing the rest of the Track U
queue.

### 1. The marker's spelling — DIRECTIVE

```pascal
function len(l: TPyList): Integer; builtin;
```

Not a registry unit listing name + tier + frontend. This is the same principle
as [[feature-a-strict-flags-scope-to-dialect-ownership-not-program-vs-unit]]
chose for dialect marking, and the same one `{$MIMIC FPC}` already embodies:
**the fact lives in the source, with the thing it describes** — explicit,
greppable, and it travels with the routine if the file moves. A registry splits
the fact from the routine and rots the moment someone adds a builtin without
updating it.

### 2. `print` as a token — DEFERRED, and recorded as a known deviation

The rule says `print` must stop being a token, because `def print` is legal
Python and today's refusal is an implementation accident. But `print` lexes to
`tkwriteln`, so the cost is a lexer change plus every parser arm keying on that
token — paid for a shape almost nobody writes.

**Deferred, and it goes in the tier table as a KNOWN DEVIATION rather than being
left to look like a rule.** That is the same judgement applied all day to
synthetic cases: the rule is right, the case is not worth the machinery yet, and
the honest move is to write down that we diverge rather than pretend we do not.
Revisit when [[feature-nilpy-thirdparty-libraries-as-targets]] trips over it —
that campaign is what would surface a real `def print`.

### 3. `--strict-python` — MOOT, it already exists

The question was whether to reserve the name. `grep -ohE '\-\-strict-[a-z-]+'
compiler/*.inc` lists it alongside `--strict-case`, `--strict-fpc`,
`--strict-uses`, `--strict-operator`, `--strict-overload`, `--strict-visibility`
and `--strict-ir`. Nothing to decide; what it *enforces* is a separate campaign
whenever someone wants one.

### Not closed by this

The two defects this ticket uncovered are filed separately and neither waited on
it: the `open` one-liner and the cross-unit overload merge. C and Zig get the
same treatment when they need it — the tiers are per-frontend by design.

**If the `print` call is wrong**, it is the one item here worth reopening on:
say so and it becomes a Track N work ticket rather than a deviation row.

## Log
- 2026-08-14 — decided, commit cf922c994.
