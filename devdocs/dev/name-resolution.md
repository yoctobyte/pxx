# Name resolution — which file, and which declaration

pxx has many frontends over one IR and one symbol table, so "what does this name
mean" is answered by more machinery than a single-language compiler needs. This
page is the map. It exists because the rules were spread across four tickets, two
of them `decided/`, and a rule that is written down only in a resolved ticket
gets re-litigated instead of read.

**Two questions wear the same slogan and must not be tangled.** Every version of
"your own language wins" applies to both, and they are different machinery:

| | question | mechanism |
| --- | --- | --- |
| **Module** resolution | which FILE does this import name load? | per-frontend extension search |
| **Symbol** resolution | which DECLARATION does this name bind to, once several are in one symbol table? | scope hiding + overload matching |

The module half is settled and mostly built. The symbol half is where the
awkward cases live, and where the unimplemented rule is.

---

## 1. Module resolution — which file

Each frontend searches **its own extension only**. A Pascal `uses math` builds
`math.pas` candidates (`parser.inc`, the uses-path search); C's `#include`
searches C headers; NilPy prefers `tkhtmlview.py`. No cross-language file search
happens implicitly, which is the intended behaviour, not an omission.

**Explicit import overrides it.** A quoted path with a foreign extension is
honoured:

```pascal
uses './math.c';     { C's exp, deliberately, not Pascal's Exp }
```

That override is what makes the symbol-level precedence below safe to adopt as a
hard rule: nothing becomes unreachable, it just has to be asked for by name.

> **Landmine:** a `uses './x.c'` whose BASENAME collides with the enclosing
> unit's name is silently dropped, no diagnostic —
> `bug-c-uses-path-basename-collides-with-enclosing-unit-name`. Don't name a
> fixture after the unit that imports it.

---

## 2. Symbol resolution — which declaration

Three rules, applied in this order. Only some of them are built.

### 2.1 Own language first — DECIDED, **NOT IMPLEMENTED**

> If a symbol is defined in more than one language, the call site's own language
> wins. A hard precedence, outranking import order. (user, 2026-08-10)

A C call to `exp` binds C's `exp`; a Pascal call to `Exp` binds Pascal's. **They
are different functions and are allowed to be** — `math.c` and `math.pas` have
different accuracy targets and edge cases. The house rule
(`normalise-dont-special-case.md`'s sibling, and the standing preference on
per-frontend helpers) says duplicated implementations per language are the
correct outcome here, not debt.

The retrospective that produced the rule: **letting C reach into Pascal's math
was the design error, not the naming.**

**Why two implementations exist at all** — and why sharing them was tried and
failed — is `math-implemented-twice.md`. Read it first if the rule looks like
needless duplication: `Round(2.5)` is 2 in Pascal and 3 in C, both correct, and
no single implementation can serve both.

**Status: `feature-a-own-language-first-symbol-resolution` (Track A, unfinished,
blocked on a design fork — see `decide-own-language-first-vs-explicit-import-in-a-case-insensitive-language`).**
The acute cause is gone — `pxxcio.pas` no longer does `uses math`, so the Pascal
RTL is no longer in scope for every C program by default. What remains is a
standing workaround: ten functions in `lib/crtl/src/math.c` are deliberately
misnamed to dodge Pascal, reached through `#define`s in crtl's `math.h`:

```c
/* NOT named `exp`: collides case-insensitively with Pascal Exp. */
double __crtl_exp(double x) { ... }
```

`__crtl_exp`, `__crtl_log2`, `__crtl_log10`, `__crtl_sin`, `__crtl_cos`,
`__crtl_tan`, `__crtl_sinh`, `__crtl_cosh`, `__crtl_tanh`, `__crtl_hypot`.
**Those ten going back to their real names, with the `#define`s deleted, is the
acceptance test for the rule.**

The `__pxx_*` PAL entry points are *not* a counter-example: they are declared in
C headers and defined in Pascal — one symbol with two halves, not two competing
definitions, so there is nothing to arbitrate.

Measured fallback, if full precedence proves expensive: requiring a
cross-language name match to **agree on case** closes the entire known collision
class (every Pascal spelling is capitalised, every C name lowercase). Safety
net, not the goal — it does not express "the native language wins".

### 2.2 Scope hiding — BUILT for routines, **MISSING for types/classes**

> A declaration hides a same-named one from an earlier or outer scope, unless
> marked `overload`.

This is FPC's rule and it is what makes `uses a, b` bind **b**'s routine (last
unit named wins) and a program's own `IntToStr` beat sysutils'. Decided in
`decide-scope-hiding-vs-flat-overload-set`, implemented 2026-08-10 (`ea0e20254`).

Before it, pxx behaved as if everything were `overload` — one flat set across
scopes with registration order as the tiebreak, i.e. the **first** unit won where
FPC takes the last.

**The gap:** it reached routines and not types. In one program today:

```pascal
program ru_m; uses ru_a, ru_b;
  WriteLn(Who);              { ROUTINE-B — correct }
  t := Thing.Create;         { CLASS-A   — wrong, FPC says B }
```

Classes and types resolve through `FindUClass`, a flat first-match that knows
nothing about scopes. Tracked as
`bug-p-scope-hiding-covers-routines-but-not-types-and-classes`. It is invisible
until two units export one type name, which is why it survived four months
unnoticed and then surfaced the moment two units both declared `Exception`.

### 2.3 Overload matching — within the winning scope

Once hiding has removed out-of-scope candidates, ordinary overload resolution
picks by argument fit. Same-scope declarations never hide each other — they are
overloads, which is what keeps `EmitAsmX64`'s `array of const` / `AnsiString`
pair alive.

### 2.4 A QUALIFIED reference bypasses hiding

`System.Random(i + 1)` must reach the builtin even though a used unit's `Random`
outranks it. A qualified call has already named its scope; hiding only answers
"which declaration does a **bare** name see". Gated on `demote` in
`MatchProcCall`.

Qualified *class* references are a separate story and were flat until recently —
see `feature-a-one-exception-class-in-a-shared-unit` for the constructor and
type-position fixes.

---

## 3. Implementation landmines

Three, and each has already cost a session.

**A lookup that returns an overload-set REPRESENTATIVE is not a binding query.**
`FindProc` returns one row of a same-named set, and the parser reads *signatures*
off it while NilPy reads *return types* off it. Ranking inside `FindProc` broke
the self-compile (`EmitAsmX64`'s `[...]` parsed as a set) and segfaulted the
NilPy stdlib at `sum(range(i))`. The fix was **candidate removal** in
`MatchElig`, plus a separate binding query `FindProcBound` for the parameterless
shape — leaving the representative alone. Expect `FindUClass` to have the same
shape.

**The two call shapes bind through different code.** `WhoP(1)` and a bare `Who`
took different paths; fixing `MatchElig` alone left the parameterless one wrong.
Test both shapes, always.

**`gate.sh quick` cannot see resolution regressions.** It passed two
previously-broken versions of the hiding fix. `make test-core` caught the
qualified-call regression; the NilPy suite caught the segfault. Anything touching
resolution wants **`--tier limited` at minimum** — the one documented exception
to the normal quick-only loop, and it is written into the tickets.

---

## 4. Status at a glance

| rule | decided | built |
| --- | --- | --- |
| module resolution per frontend extension | yes | yes |
| explicit foreign-path import overrides | yes | yes |
| own language first (symbols) | yes, 2026-08-10 | **no** — `feature-a-own-language-first-symbol-resolution` |
| scope hiding, routines | yes | yes, `ea0e20254` |
| scope hiding, types/classes | yes (same rule) | **no** — `bug-p-scope-hiding-covers-routines-but-not-types-and-classes` |
| qualified reference bypasses hiding | yes | yes (routines); classes fixed on the exception branch |

The user-facing half of this — "your own language wins, and an explicit import
overrides it" belongs in the language reference — is **not** written yet and is a
Track D job; this page is the internal map.
