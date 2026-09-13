---
slug: bug-n-a-call-result-discarded-in-a-boolean-context-is-never-released
title: a call result discarded in a boolean context is never released
summary: >
  `if "b,a".split(","):` leaks the list, one per evaluation, and so does
  `if re.match(p, s):` and `if re.findall(p, s):`. Binding the same call to a
  local first is CLEAN, and a discarded list LITERAL is clean, so this is the
  discard path for a CALL RESULT specifically -- not a container bug and not an
  `re` bug. Measured 3000 iterations under -dPXX_ALLOC_CENSUS: bound `mo =
  re.match(...); if mo:` gives live=8, the discarded spelling gives live=3000;
  `"b,a".split(",")` discarded gives ~3.7/iteration. The output is correct in
  every case, so no expect_same row can see it -- only the census can.
track: N
type: bug
prio: 45
owner: unassigned
status: open
---

## Measured 2026-09-13 (frankS), 3000 iterations, -dPXX_ALLOC_CENSUS

The whole finding is one contrast, and the CONTROL is the important half:

    mo = re.match("b","banana"); if mo:      live=8        BOUND    clean
    if re.match("b","banana"):               live=3000     DISCARDED 1/iter
    r = re.findall("a","banana"); len(r)     live=13       BOUND    clean
    if "b,a".split(","):                     live=11129    DISCARDED ~3.7/iter
    if ["a"]:                                live=3        LITERAL  clean

`str.split` is the row that makes it general: it is not `re`, it is not a shim
with an unusual return, and it leaks the same way. `if ["a"]:` is the row that
locates it: a discarded LITERAL is released correctly, so the discard machinery
exists and a CALL result is what misses it.

## Why nothing caught it

The values are all correct -- every one of these programs prints the right
answer. A leak cannot fail a value check, which is the class CLAUDE.md records
under "MATCH THE ASSERTION CLASS TO THE DEFECT CLASS". Found only because a
census was being run for an unrelated reason
([[bug-n-a-module-level-regex-call-recompiles-and-leaks-its-pattern]]), and the
residue did not go to zero after that fix.

## Scope not yet established

Measured for `if <call>:` only. NOT measured, and someone should before ranking
this higher or lower:

- `while <call>:`, `and`/`or` operands, a call as a bare expression statement
- a call result discarded as a function ARGUMENT that is then dropped
- whether the leak is the object only or also what it owns (the 3.7/iteration
  for `split` against 1 for `match` suggests the ELEMENTS go too, but the two
  return different shapes and that was not isolated)

Do not assume the `if` result generalises; the literal-versus-call asymmetry
above is exactly the kind of boundary that moves when the spelling changes.

## Positive control for whoever takes it

`if ["a"]:` must STAY clean (live=3) -- it is the arm that already works, and a
fix that releases a call result by making the discard path more aggressive could
double-release the literal. And the assertion has to be a census bound over a
LOOP: a handful of iterations cannot separate a per-iteration leak from a fixed
residue, which is the whole reason this sat unnoticed.
