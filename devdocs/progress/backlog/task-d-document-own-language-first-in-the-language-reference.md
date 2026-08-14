---
track: D
prio: 40
type: task
blocked-by: [feature-a-own-language-first-symbol-resolution]
summary: "The user-facing half of the name-resolution rules: 'a name from your own language wins, and an explicit foreign import overrides it'. Internal map is devdocs/dev/name-resolution.md; the language reference says nothing. Blocked until the symbol rule is actually built — documenting behaviour the compiler does not have is worse than documenting nothing."
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
