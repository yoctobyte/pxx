---
track: D
prio: 50
type: bug
blocked-by: []   # decided 2026-08-16: not a compiler bug, see the resolution at the bottom
summary: "NOT A COMPILER BUG — re-aimed at docs 2026-08-16. The cross-language qualifier exists and always did: `uses './mymath.c' as cmath;` then `cmath.cube(3)`. This ticket only ever measured the UNALIASED form. What is left is the docs fix: docs/language/name-resolution.md ships a Current-status note saying the escape does not exist."
status: done
owner: frank2-D
---

# No qualified syntax for a cross-language import

Found while writing `docs/language/name-resolution.md`
([[doc-cross-language-name-resolution-rules]], Track D). Filed, not fixed —
Track D does not touch `compiler/**`.

## The claim this contradicts

`devdocs/dev/name-resolution.md` §2.4 and
[[decide-own-language-first-vs-explicit-import-in-a-case-insensitive-language]]
both rest on qualification being the universal escape:

> Qualification is the escape **and always works**.

It works for a Pascal unit. It does not exist for a foreign-language import.

## Measured (pinned, `stable_linux_amd64/default/pinned`, 2026-08-14)

Pascal-unit qualification — works:

```pascal
program qual2;
uses pu;                     { pu declares Cube, returning 222.0 }
function Cube(x: Double): Double;
begin Cube := 999.0; end;
begin
  WriteLn(Cube(3.0):0:1);    { 999.0 — local shadows }
  WriteLn(pu.Cube(3.0):0:1); { 222.0 — qualified reaches pu's }
end.
```

Cross-language qualification — no such thing:

```pascal
program qual;
uses './mymath.c';           { mymath.c: double cube(double x) }
function cube(x: Double): Double;
begin cube := 999.0; end;
begin
  WriteLn(mymath.cube(3.0):0:1);
end.
```

```
pascal26:8: error: undefined variable (mymath)
```

A `uses './x.c'` introduces the C file's symbols into scope but binds no
qualifier name for the file, so there is no phrase that means "C's `cube`".

## Why it matters more than it looks

The case rule ([[feature-a-own-language-first-symbol-resolution]] rule 2) is
what makes own-language-first safe: `exp` and `Exp` never compete, so nothing
becomes unreachable. That argument holds only while the *spellings differ*. The
moment a Pascal declaration and a C one agree on case — the exact case the warn
rule is written for — the loser is unreachable with no way to ask for it, and
the documented escape is not there.

So this is the missing half of the rule set, not a cosmetic gap: rule 3 says
"warn where a genuine ambiguity survives, qualification is the escape", and for
the cross-language case the escape does not exist. Worth settling **before**
[[feature-a-own-language-first-symbol-resolution]] lands, since that ticket's
acceptance test (renaming the ten `__crtl_*` functions back) recreates exactly
this shape on purpose.

## Options (Track U may need to pick)

1. **Bind the basename as a qualifier** — `uses './mymath.c'` makes `mymath` a
   scope name, like a Pascal unit. Cheapest to explain; collides with the known
   landmine `bug-c-uses-path-basename-collides-with-enclosing-unit-name`.
2. **A language-tagged qualifier** — a reserved scope, e.g. `C.cube`, that means
   "the C-frontend declaration". Unambiguous, one new name to reserve, and it
   reads at the call site as the language boundary it is.
3. **Accept it and require renaming in the C source.** Status quo; this is what
   the ten `__crtl_*` `#define`s already are, and the standing plan is to
   *delete* them, so this option undoes the acceptance test.

Recommendation: option 2, and note in
[[decide-own-language-first-vs-explicit-import-in-a-case-insensitive-language]]
that the "always works" claim needs an amendment either way.

## Documented meanwhile

`docs/language/name-resolution.md` ships with this listed under **Current
status**: "Qualification has no syntax for a cross-language import. Distinguish
those by case, or rename." Update that section when this resolves.

## Gate

`make compiler/pascal26` + the two programs above, then `tools/gate.sh quick`.


## ESCALATED 2026-08-15 (Track A+N session)

Not fixed: every option here either reserves a global name or changes what
`uses` binds, and the ticket's own text says Track U may need to pick. Filed as
[[decide-cross-language-qualifier-syntax]] with the three options, a
recommendation (option 2, with option 1 as a later addition rather than an
alternative — they answer different questions), and one measured fact the
options list was missing: **nothing in `lib/**` declares a unit named `C`, but
`C` is an ordinary variable name in this repo** (two `test/*.pas` programs use
it). So option 2 must resolve `C` only in QUALIFIER position, never as a
reserved word — otherwise it breaks existing Pascal, which decides the
implementation shape before anyone starts it.


## RESOLVED-AS-NOT-A-BUG 2026-08-16 (user, Track U) — the escape existed the whole time

[[decide-cross-language-qualifier-syntax]] is decided, and the answer is none of
the three options above. It is the alias clause:

```pascal
uses './mymath.c' as cmath;
WriteLn(Cube(3));        { 27   — Pascal's }
WriteLn(cmath.cube(3));  { 1027 — C's      }
```

Verified on the same pinned binary this ticket measured against.
[[feature-uses-alias-as]] landed **2026-06-30**, six weeks before this was
filed. It works across the language boundary because the alias maps to the
**real unit's `Strs[]` index** rather than registering a namespace of its own —
so the C file's symbols, which are already tagged with that index, are reachable
through it.

### The methodological miss, worth more than the ticket

The measurement here was correct and the conclusion drawn from it was not. The
repro exercised `uses './mymath.c';` — the bare form — found no qualifier, and
generalised to "a `uses './x.c'` binds no qualifier name for the file, so there
is no phrase that means C's `cube`". The bare form indeed binds nothing. The
*aliased* form was never tried, and it is the one the dialect documents as the
answer to unqualifiable unit names — its own ticket opens with `uses
'wayland-client' as wayland;` for exactly this reason: a quoted unit name has no
usable qualifier until you give it one.

One negative result, generalised past what it measured, produced a Track A bug,
a Track U escalation, and a three-option language-design debate. **Try the
existing escape before concluding the escape does not exist** — and when a
feature's own ticket says it solves "quoted unit names cannot be qualified",
that is the same sentence as this bug's title.

### What is left, and it is Track D only

`docs/language/name-resolution.md` ships this under **Current status**:

> "Qualification has no syntax for a cross-language import. Distinguish those by
> case, or rename."

That is published, user-facing, and wrong. Replace it with the alias form.
`devdocs/dev/name-resolution.md` §2.4 is already amended (the unqualified
"qualification always works" sentence that started this).

Retracked A -> D. No `compiler/**` change is needed or wanted.
Fold into [[docs-name-collisions-and-the-as-escape]] if that lands first.

## Resolved 2026-08-19 (Track D, pin v364)

The wrong note is gone, and it was wrong in a way the ticket did not predict.
Measured first:

```pascal
uses './mymath.c' as cmath;
function Cube(x: Double): Double; begin Cube := 27.0; end;
...
WriteLn(Cube(3.0):0:1);        { 27.0   — Pascal's, bare }
WriteLn(cmath.cube(3.0):0:1);  { 1027.0 — C's, qualified }
```

So cross-language qualification not only exists, it composes with ordinary
scope hiding exactly as the page's Pascal-unit example does. The
"Current status" bullet claiming otherwise is replaced — not deleted, but
replaced with the limit that is actually true today: `from '<file>' import
<name>` is not built (*expected a module name after from*).

`docs/language/name-resolution.md` also got the module-resolution section
rewritten around the semantics that landed in v364, and now links the new
`docs/language/name-collisions.md` page.

## Log
- 2026-08-19 — resolved, commit d45d131ad.
