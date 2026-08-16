---
track: D
prio: 45
type: task
blocked-by: []
summary: "The user-facing 'how do I deal with a name collision' page. Two languages in one program will both declare `cube`, and the answer — `uses './mymath.c' as cmath;` then `cmath.cube(...)`, or `import mymath as cmath` from NilPy — is true TODAY and documented nowhere. Not blocked, unlike the own-language-first doc ticket: this describes behaviour that already ships."
---

# Document how to deal with name collisions

Asked for by the repo owner, 2026-08-16, while deciding
[[decide-cross-language-qualifier-syntax]].

## Why this is its own page

A program that mixes languages *will* hit two declarations of one name — that is
not an edge case, it is the normal consequence of `uses './mymath.c'` next to a
Pascal `Cube`. The answer is short, it works today, and no user-facing document
says it.

Distinct from [[task-d-document-own-language-first-in-the-language-reference]],
which is **blocked** on `feature-a-own-language-first-symbol-resolution` being
built. That ticket documents the *rule* that decides which declaration a bare
name binds to. This one documents the *escape* — how to name the other one — and
the escape already ships, so it can be written now. When the rule lands the two
pages become neighbours, not duplicates.

## What it has to say

1. **A bare name binds by the resolution rules; a qualified name asks for a
   specific scope.** Qualification is the escape from any hiding.
2. **A Pascal unit already has a scope name**: `uses pu;` -> `pu.Cube(3)`.
3. **A foreign file has to be GIVEN one, with `as`:**

   ```pascal
   uses './mymath.c' as cmath;

   function Cube(x: Integer): Integer;    { Pascal's own }
   begin Cube := x * x * x; end;

   begin
     WriteLn(Cube(3));        { 27   — the bare name is Pascal's }
     WriteLn(cmath.cube(3));  { 1027 — C's, asked for by name    }
   end.
   ```

   This is `feature-uses-alias-as` (landed 2026-06-30) and it is the same clause
   that makes `uses 'wayland-client' as wayland;` usable.
4. **Bare `uses './mymath.c';` binds no scope, on purpose.** The file's full
   name is `mymath.c`; a second dot in `mymath.c.cube` would be worse than
   asking for the alias. Say this, so a reader who tries `mymath.cube` and gets
   `undefined variable (mymath)` finds the answer instead of filing a bug — one
   already was (`docs-cross-language-qualifier-note-is-wrong`).
5. **From NilPy, Python's own spelling already does both**: `import mymath` binds
   the bare name and `import mymath as cmath` renames it, exactly as CPython
   does. The asymmetry with Pascal is each language keeping its own rule, not an
   inconsistency — worth one sentence so it does not read as an accident.
6. **Which direction the traffic goes.** C is the lingua franca — how languages
   reach each other's compiled libraries — and Pascal/Python importing C is the
   common, fully-supported case. C importing Pascal or Python **works**, but
   under real restrictions: the advanced typing (strings, variants, objects) is
   not trivially solved in that direction, and a small wrapper is the normal
   answer. Set that expectation rather than leaving a reader to discover it.

## Not in scope

- The own-language-first *rule* itself — that is the blocked ticket above.
- Scope hiding / `uses` order (`uses a, b` binds b's) is ordinary Pascal
  semantics and belongs with units and scope in the reference.
- Any proposal for new syntax. `C.cube`, language tags and sigils were all
  considered and rejected in `decide-cross-language-qualifier-syntax`; do not
  reintroduce them as "future work" in a user-facing page.

## Gate

Track D's usual: no `compiler/**` or `lib/**` changes; **compile every snippet
against `$(PXX_STABLE)` and run it** — the four-row table in the decide ticket
was produced that way and is what caught the original claim being false. Do not
paraphrase this ticket; verify against the compiler at the time of writing.

Also fix, or fold in, [[docs-cross-language-qualifier-note-is-wrong]]:
`docs/language/name-resolution.md` currently ships "Qualification has no syntax
for a cross-language import. Distinguish those by case, or rename." under
**Current status**, which is published and wrong.
