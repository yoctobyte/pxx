---
track: A
prio: 50
type: bug
blocked-by: []
summary: "Qualification is the documented escape from scope hiding — `pu.Cube` reaches a shadowed Pascal unit's routine — but there is NO equivalent for a cross-language import: a `uses './mymath.c'` binds no qualifier, so `mymath.cube` is `undefined variable (mymath)`. Once a Pascal `Cube` is in scope, C's `cube` becomes unreachable. Measured against pinned, 2026-08-14."
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
