---
track: U
prio: 50
type: decide
blocked-by: []
status: decided
summary: "DECIDED 2026-08-16: none of the three proposed syntaxes. The escape is `uses './mymath.c' as cmath;` + `cmath.cube(...)`, which feature-uses-alias-as shipped 2026-06-30 and which reaches foreign symbols because the alias maps to the REAL unit's Strs[] index. Verified on pinned. Bare `uses './x.c'` stays unbound deliberately. The originating bug is a docs fix, not a compiler one."
---

# What is the syntax for "the C declaration of this name"?

Escalated from [[docs-cross-language-qualifier-note-is-wrong]] (A, p50),
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

## DECIDED 2026-08-16 (user) — none of the three. `uses .. as ..`, which already ships

**No new syntax.** Not `C.cube`, not a sigil, not a reserved scope, and not
"rename it in the C source". The escape is the alias clause the dialect already
has:

```pascal
uses './mymath.c' as cmath;
...
WriteLn(Cube(3));        { 27   — Pascal's own }
WriteLn(cmath.cube(3));  { 1027 — C's          }
```

The user's reasoning, and it is the whole decision: *"as soon as we have
`uses .. as ..`, this problem is trivially solved without ambiguity"* — and
[[feature-uses-alias-as]] landed **2026-06-30**. It was already solved when this
ticket was filed; nobody checked.

### Measured on pinned before deciding, all four shapes

| form | result |
| --- | --- |
| Pascal `uses './mymath.c' as cmath;` -> `cmath.cube(3)` | **1027** — works |
| NilPy `import mymath as cmath` -> `cmath.cube(3)` | **1027** — works |
| NilPy `import mymath` -> `mymath.cube(3)` | **1027** — bare name binds, as CPython |
| Pascal `uses './mymath.c';` -> `mymath.cube(3)` | `undefined variable (mymath)` |

That last row is the only thing the originating bug ever measured, which is how
"there is no qualifier at all" got written down next to a working one.

`feature-uses-alias-as` maps the alias to the **real unit's `Strs[]` index**
rather than registering a new compiled unit, which is exactly why it reaches
foreign symbols too — the alias is not a namespace of its own, it is a second
name for the one the C file's symbols are already tagged with.

### Sub-fork, also decided: bare `uses './x.c'` stays UNBOUND

It will not bind `mymath` as a scope. The user: *"the full name is `mymath.c`
and the extra dot would confuse us — this is exactly why the `..as..` use case
was intended."* Two independent reasons to keep it that way:

- `mymath.c.cube` is worse than requiring an alias, and a basename-derived scope
  would have to silently drop the extension to avoid it;
- it steps around [[bug-c-uses-path-basename-collides-with-enclosing-unit-name]]
  (a basename matching the enclosing unit is silently dropped) instead of making
  that collision load-bearing.

The asymmetry with NilPy is not a defect: Python's `import` binds a name by
definition, Pascal's `uses` never has. Each follows its own language's rule.

### Scope, narrowed deliberately — do not reopen

The qualifier belongs to the **importing** language, and C's own frontend stays
clean. C is the lingua franca — the way languages reach each other's compiled
libraries — so the traffic across that boundary is not symmetric in *effort*: C
**can** import Pascal and Python today, but with far more restriction, because
the advanced typing (strings, variants, objects) is not trivially solved in that
direction. Pascal and Python importing C is the common case and the one that
carries the collision-handling machinery; going the other way, a small wrapper
covers it, and rich applications are not written in C here.

Consequences of that, stated so they are choices rather than omissions:

- **C-vs-C** (two C files both declaring `cube`) — out of scope. Alias each.
- **C-vs-Zig with the same basename** — out of scope; the alias distinguishes
  them anyway, which is the second reason a *language* tag was the wrong axis.
- No `Zig.` / `Rust.` / `Py.` tag is reserved either, now or later.

### What this changes elsewhere

- [[docs-cross-language-qualifier-note-is-wrong]] — not a compiler bug.
  Re-aimed at the docs; its option list never included the alias clause.
- `devdocs/dev/name-resolution.md` §2.4 — the "qualification **always works**"
  claim is amended in place: a qualifier exists whenever the import NAMES a
  scope, which for a foreign file means `as`. That single unqualified sentence
  is what produced this ticket.
- [[feature-a-own-language-first-symbol-resolution]] — unblocked as far as this
  goes. Its acceptance test (the ten `__crtl_*` `#define`s going back to their
  real names) needs a working escape from the Pascal side, and row 1 above is
  it.
- New Track D ticket [[docs-name-collisions-and-the-as-escape]] — the
  user-facing "how to deal with name collisions" page. NOT blocked, unlike
  [[task-d-document-own-language-first-in-the-language-reference]]: the escape
  is true today, the own-language-first *rule* is not yet.
