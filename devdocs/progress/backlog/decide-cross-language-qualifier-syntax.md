---
track: U
prio: 50
type: decide
blocked-by: []
summary: "There is no way to say \"C's cube\" once a Pascal Cube is in scope — qualification, the documented universal escape, has no cross-language form. Pick the syntax: file basename as a scope, a reserved language tag (C.cube), or rename in the source. Blocks the own-language-first rule, whose own acceptance test recreates the collision on purpose."
---

# What is the syntax for "the C declaration of this name"?

Escalated from [[bug-no-qualified-syntax-for-a-cross-language-import]] (A, p50),
which is otherwise ready. The bug is measured and not in doubt; what is missing
is a language-design call, and it reserves a name or changes what `uses` binds
either way. Both are yours.

## The gap in one line

`devdocs/dev/name-resolution.md` §2.4 rests on "qualification is the escape and
**always works**". For a Pascal unit it does: `pu.Cube` reaches the shadowed
routine. For `uses './mymath.c'` there is no qualifier at all — `mymath.cube` is
`undefined variable (mymath)`, so once a Pascal `Cube` is in scope the C `cube`
is unreachable with no phrase that asks for it.

This is not cosmetic. Own-language-first is safe *because* qualification is the
escape; and [[feature-a-own-language-first-symbol-resolution]]'s acceptance test
— renaming the ten `__crtl_*` functions back to their plain names — recreates
exactly this collision on purpose. So the escape has to exist before that lands.

## The options, as the bug ticket frames them

**1. Bind the file basename as a scope.** `uses './mymath.c'` makes `mymath` a
qualifier, exactly like a Pascal unit name.

- Cheapest to explain: one rule, no new reserved word, and it is what a reader
  already expects `uses` to do.
- Walks into a known landmine:
  [[bug-c-uses-path-basename-collides-with-enclosing-unit-name]] — a basename
  that matches the enclosing unit's name is silently DROPPED today. Binding the
  basename as a scope makes that collision louder rather than quieter, so that
  bug becomes a prerequisite.
- Says nothing about the language, only about the file. Two C files both
  declaring `cube` are still distinguishable; a C and a Zig file with the same
  basename are not.

**2. A reserved language tag — `C.cube`, and later `Zig.`, `Rust.`, `Py.`.**

- Unambiguous, and it reads at the call site as the boundary it actually is.
- Costs a reserved scope name. Checked: nothing in `lib/**` declares a unit
  named `C`, but `C` as an ordinary identifier is everywhere (two test programs
  in `test/*.pas` use it as a variable name). So this must be a scope resolved
  only in the qualifier position, never a reserved WORD — otherwise it breaks
  existing Pascal, which is not acceptable.
- Does not distinguish two C files from each other. In practice the collision
  being solved is Pascal-vs-C, not C-vs-C, so this may simply be the right
  granularity — but say so deliberately rather than discovering it later.

**3. Accept it; require renaming in the C source.** Status quo. This is what the
ten `__crtl_*` `#define`s are, and the standing plan is to DELETE them — so
choosing this un-picks that plan and should be recorded as such.

## Recommendation

**2, with 1 as a later addition rather than an alternative.** They answer
different questions — "which language" and "which file" — and a codebase that
grows a second C file with a clashing name will want both. Starting with the
language tag settles the case the own-language-first rule actually depends on,
without waiting for the basename-collision bug to be fixed first.

The part that is genuinely yours: whether a bare `C` in qualifier position is a
price worth paying, given that `C` is a perfectly ordinary variable name in this
repo today. A less collision-prone spelling (`@C.cube`, `lang.C.cube`) trades
readability for safety, and which side of that trade you want is not something
the code can tell me.

Either way, [[decide-own-language-first-vs-explicit-import-in-a-case-insensitive-language]]
needs its "qualification always works" claim amended, and
`docs/language/name-resolution.md` has the gap under **Current status** waiting
to be replaced by whatever this resolves to.
