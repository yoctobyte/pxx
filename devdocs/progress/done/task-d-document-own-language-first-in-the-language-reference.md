---
track: D
prio: 15
type: task
blocked-by: [feature-a-own-language-first-symbol-resolution]
summary: "The user-facing half of the name-resolution rules: 'a name from your own language wins, and an explicit foreign import overrides it'. Internal map is devdocs/dev/name-resolution.md; the language reference says nothing. Blocked until the symbol rule is actually built — documenting behaviour the compiler does not have is worse than documenting nothing."
status: done
owner: frankD
---

# Document own-language-first in the public language reference

`devdocs/dev/name-resolution.md` maps the whole picture for compiler work. The
**user-facing** rule has no home in `docs/**`, and it is a rule programmers hit:

- an import name resolves to a file in **your own language** (`uses math` finds
  `math.pas`, `#include <math.h>` finds C's);
- a symbol defined in more than one language binds to **your own language's**;
- **an explicit import overrides both** — `uses './math.c'` from Pascal gets C's
  functions, deliberately, with no conflict to arbitrate because you named the
  file.

That last point is what makes the rule feel like a feature rather than a
restriction, and it is the part most likely to be missed: nothing becomes
unreachable, it just has to be asked for by name.

## Blocked, deliberately

`feature-a-own-language-first-symbol-resolution` is **decided but not built**.
The module half is real today; the symbol half is not. Documenting the symbol
rule now would describe behaviour the compiler does not have — and this is a
public doc the website publishes verbatim from git.

Write it when that ticket lands. The acceptance test named there — the ten
`__crtl_*` names in `lib/crtl/src/math.c` going back to their real spellings —
is also the signal that this is safe to document.

## Not in scope

Scope hiding / uses order (`uses a, b` binds b's) is ordinary Pascal semantics
and belongs wherever the reference already covers units and scope, not here.
Check whether it is covered at all — it may be its own small gap.

## Gate

Track D's usual: no compiler or `lib/**` changes, snippets compile against
`$(PXX_STABLE)`, and the claims match what the compiler actually does at the
time of writing (verify by compiling, don't paraphrase this ticket).

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.

---

## RESOLVED 2026-08-29 (frankD)

The blocker (`feature-a-own-language-first-symbol-resolution`) is **done**, so
this was genuinely unblocked. The ticket's own release signal — the ten
`__crtl_*` names going back to their real spellings — has been met: `lib/crtl/src/math.c`
no longer carries them.

But the ticket assumed the page said *nothing* about the symbol rule. It says
plenty, and most of it is right. What was actually wrong was the **status
section**, in both of its first two bullets.

### The page was telling readers the feature does not exist

`## Current status` carried:

> **Own-language-first is not yet implemented as an explicit precedence.**

Measured on v393 — it is. With `cm.c` defining `exp` returning 42.0:

| program | 2026-08-14 (in the blocker) | today |
| --- | --- | --- |
| `uses math, './cm.c'` | `42.0` — Pascal hijacked | **`2.7183`** |
| `uses './cm.c', math` | `42.0` | **`2.7183`** |

So the precedence is real *and* outranks import order, which is exactly what the
`### Your own language wins` section already claimed. Rewritten to say what is
actually still missing — **the diagnostic**. An ambiguous cross-language bare
call resolves silently; no warning is emitted, with or without any `--warn-*`
flag. That half of the old bullet was true and is kept.

The nearby aspirational sentence (*"the compiler's obligation is to warn and name
what it picked"*) now says the warning is not emitted yet and points at the
status section, so the page cannot be read as promising a diagnostic that does
not fire.

### The second bullet was simply wrong

> **Scope hiding covers routines, not types and classes.** Two units exporting
> the same *class* name still resolve first-match rather than last-named.

`test_scope_hiding_types.pas` and its `_rev` twin both run green and show
last-named winning for **routine, class, const, alias, record, array and enum** —
in both clause orders. Bullet deleted rather than reworded; there is nothing left
of it. (The Makefile comment beside those tests says as much: *"The routine row
alone used to be right."*)

Bullet three (`from '<file>' import <name>` not built) re-checked and **still
accurate** — the error is verbatim *expected a module name after from*.

### The content the ticket actually wanted, and it was missing

The ticket's point — *"that last point is what makes the rule feel like a feature
rather than a restriction, and it is the part most likely to be missed"* — was
the one thing the page did not have. `### Qualification reaches past the shadow`
covered Pascal-unit and builtin qualification, but not the **cross-language**
form. Added `#### Across languages, give the file a scope name` with a worked
example that shows all three cases at once:

- `Exp(1.0)` → `2.7183`, Pascal's own, as the rule says;
- `cmath.exp(1.0)` → `42.0000`, C's, asked for by name;
- `cube(3.0)` → `27.0`, a foreign name that collides with nothing, unqualified.

**One correction to the ticket's framing while writing it.** The ticket says
*"an explicit import overrides both — `uses './math.c'` from Pascal gets C's
functions"*. That is no longer true for a **colliding** name: a plain
`uses './cm.c'` now loses to Pascal's own `Exp`, by design, and the override
requires the `as` scope-name form. The blocker's own Track U note confirms this
is intended (*"nothing becomes unreachable, it just has to be asked for by
name"*). The page documents the `as` form, not the plain import, as the escape.

### Out of scope, as instructed

Scope hiding is ordinary Pascal semantics and the page already covers it — the
ticket asked whether it was a gap; it is not, and it is now *correctly* covered
since the stale bullet is gone.

### Measured — pinned v393, no rebuild

Both clause orders; the control (`uses math` alone → 2.7183); a unique C name
unqualified; the qualified `cmath.exp`; the absence of any warning; both
scope-hiding tests; the `from` refusal. The page's own example was extracted from
the rendered Markdown, compiled and run — it prints the three values its inline
comments claim.
