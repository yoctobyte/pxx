---
slug: bug-p-a-generic-template-in-a-unit-may-reference-a-non-global-symbol
title: "A generic template declared in a unit can bind a symbol from the USING program, and nothing says no"
track: P
prio: 30
type: bug
blocked-by: []
status: backlog
owner: ""
created: 2026-09-05
summary: "tgeneric4.pp specializes a generic declared in ugeneric4 at a point where the program has its own LocalFill; the template must bind the unit\'s, and FPC refuses the whole construct with `Global Generic template references static symtable`. pxx accepts it silently. It scored as a pass until 2026-09-05 only because the parser could not read ugeneric4 at all — the accidental-pass shape, third instance."
---

# The shape

`ugeneric4.pp` declares `generic TList<_T>` whose `Fill` method calls
`LocalFill`. The program `tgeneric4.pp` declares its OWN `LocalFill`, then
specializes. FPC refuses at the DECLARATION:

```
ugeneric4.pp(28,4) Error: Global Generic template references static symtable
```

The test is `{ %fail }` — the compile must be rejected. pxx compiles it and runs
it. **We have no diagnostic for a generic template referencing a symbol that is
not global**, so the binding is decided silently and the test's own comment says
what that costs in FPC's model: the assembler symbol is not global and would
fail at link time.

# Why it only became visible now

**It was passing for a reason unrelated to what it tests.** Pin v403 refuses the
file with:

```
pascal26:8: error: expected '>' before '>='
  in: ugeneric4.pp
```

— the unit spells its header `generic TList<_T>=class(...)` with no space, which
lexed as one `tkGe` token. A `%FAIL` row scores ANY refusal as a pass, so the
row was green because the parser stopped at the header. Fixing that lexing
detail (feature-pascal-corpus-fpc-testsuite) removed the accident and the row
went red the moment the compiler could read the file.

**Third instance of this exact shape**, and the two before it are
[[bug-p-a-generic-routines-implementation-type-parameters-are-not-checked-against-its-interface]]
(tgenfunc17, tgenfunc18, exposed the same way by `71deb21d4`). A `%FAIL` row is
a pass-by-refusal, so every parser capability we add can turn one red, and each
one is a missing diagnostic that was always missing.

# What to do

Decide first whether we WANT the diagnostic. CLAUDE.md ranks a differing
diagnostic as deferred, and this is not a differing one — it is an absent one on
a construct FPC rejects outright, so a program relying on it is relying on
something FPC will not build. That makes it closer to `accepts-invalid` than to
compat.

If the answer is no, this belongs in `pxx.skip` tagged `accepts-invalid:` and in
`known-incompat/`, NOT left as a red row — a permanently red conformance row is
a single-slot channel that hides the next real regression behind it.

**Do not "fix" it by re-breaking the header parse.** That is what was providing
the green.

# Gate

`tools/run_pascal_conformance.sh` — tgeneric4.pp must move from
`fail(accepted-invalid)` to pass-by-rejection, with the refusal naming the
template/symtable problem and not something incidental. Check WHY it refuses,
not that it refuses.
