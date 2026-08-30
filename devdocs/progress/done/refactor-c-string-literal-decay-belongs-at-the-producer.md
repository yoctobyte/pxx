---
track: C
prio: 50
type: refactor
blocked-by: []
summary: "The +8 that turns a C string literal's handle into a char* was duplicated at FOUR consumers (assign, return, call argument, binop -- the ticket listed three), each keyed on `ASTKind[...] = AN_STR_LIT`, so any wrapper node defeated them all. NOT latent: a census of 13 wrappers x 5 sites against gcc found FIVE live wrong values, every one a comma operator, each returning an empty string rather than crashing. Fixed by decaying once at the producer arm under CProgramMode. RESOLVED 2026-08-30 by frankC."
status: done
---

# C string-literal decay belongs at the producer

Follow-up to `done/bug-c-a-pointer-cast-of-a-string-literal-points-at-the-length-prefix.md`,
which fixed the symptom by making a pointer cast of a literal an identity. The
underlying shape is still there.

## The shape

A string literal lowers to `IR_CONST_STR`, whose value is the frozen string's
**handle**: an 8-byte length prefix followed by the char data. C wants the data
pointer. So each consumer adds 8 for itself, in `compiler/ir.inc`:

| site | test |
| --- | --- |
| assignment | `CProgramMode and (ASTKind[ASTRight[node]] = AN_STR_LIT) and (lhsTk = tyPointer)` |
| `return` | the same on `ASTLeft[node]`, with a pointer return type |
| call argument | the same idea in the `tyString`->`tyPointer` marshalling |

Each carries its own comment pointing at the other two. Three copies of one
rule is what `devdocs/dev/root-cause-over-microfix.md` calls a design flaw
rather than a smell, and the failure mode is specific and nasty: the tests ask
about the node kind of *their own operand*, so **any** node in between defeats
all three at once. A cast did exactly that, and assignment, return and argument
passing all went wrong together — which made one shallow bug look like a deep
one.

Anything else that ever wraps a literal — a conditional operator yielding one,
a comma, a parenthesised compound expression, a future constant-folding node —
reintroduces the same bug in the same three places.

## What to do instead

In C mode a string literal has no other meaning: it IS a `char *`. So lower
`AN_STR_LIT` to `handle + 8` once, in the producer arm of `IRLowerAST` under
`CProgramMode`, and delete the three consumer skips. `sizeof "abc"` and the
array-ness of a literal are handled in the front end and do not read the IR
value, but check them; the indexing arm (`ir.inc` around the `AN_STR_LIT` base
case) computes its own base and must be re-pointed or left consistent.

## How to judge it

`--tier quick` is not the judge here. The C corpora — zlib, sqlite, quickjs,
tcc, lua — are what actually exercise every string path, and they run on Track
T. Land this behind a full corpus run, not a quick gate.

## Ownership: this is a Track A change, not Track C — 2026-08-29 (frankC)

Raised by frankC and routed to **A** by frank-coordinator. Recording the reason,
because the ticket's own `track: C` reads the other way and the next agent will
hit the same fork:

The change lands in `compiler/ir.inc` (`IRLowerAST`'s producer arm, plus the
three consumer skips). Two rules in CLAUDE.md point in opposite directions —
Track C owns *"C-exclusive C→IR lowering"*, and *"anything in `lexer.inc`,
`ir*.inc`, `symtab.inc`, `defs.inc`, the backends → file a Track A ticket, do not
edit it under Track C."* **The second wins: file-lanes exist for collision
avoidance, not as a taxonomy, so the rule is about the FILE and not the topic.**
A C-exclusive change under `CProgramMode` that happens to live in a shared file
is still a shared-file edit, and two agents in `ir.inc` is exactly the collision
the letters exist to prevent.

`track:` left as `C` deliberately — it is a C-frontend defect and belongs in C's
queue for visibility — but **the edit needs the A slot**. Whoever takes it should
hold Track A or confirm no one else is in `ir.inc`.

Nothing here is started; no code was touched. The analysis in the sections above
is the handoff — it should not need re-deriving.

## RESOLVED — 2026-08-30 (frankC)

**It was not a refactor.** Opened at HEAD before starting, as the dispatch
required, and the shape the ticket describes as latent is **live**: five
ordinary expressions produce a silent wrong value today.

```c
return (1, "s")                          -> "" (gcc: "s")
return (1, (2, "s"))                     -> ""
return (const char *)(1, "s")            -> ""
return (1, (const char *)"s")            -> ""
const char *v = (const char *)(1, "s")   -> ""
```

Every one is a **comma operator** — the wrapper nobody had tested. The returned
pointer sits on the frozen string's 8-byte length prefix, whose first byte is
the length and whose remainder is zero, so it prints as an empty string: a
wrong answer that looks like an empty answer, which is the quiet kind.

## The census

An enumeration, not a search: **every way to wrap a literal** x **every site
that consumes one**, 13 x 5, gcc deciding each cell
(`tools/c_strlit_decay_census.py`, now in the repo and indexed in
`devdocs/dev/differential-probes.md` with its blind spots).

```
site      plain paren paren2 comma comma-nested tern-T tern-F cast cast-comma comma-cast tern-comma comma-tern cast-tern
assign    ok    ok    ok     ok    ok           ok     ok     ok   FAIL       ok         ok         ok         ok
return    ok    ok    ok     FAIL  FAIL         ok     ok     ok   FAIL       FAIL       ok         ok         ok
arg       ok    ok    ok     ok    ok           ok     ok     ok   ok         ok         ok         ok         ok
init-st   ok    ok    ok     n/a   n/a          ok     ok     ok   n/a        n/a        n/a        n/a        ok
direct    ok    ok    ok     ok    ok           ok     ok     ok   ok         ok         ok         ok         ok
```

**5 wrong of 59 measured, and 6 `n/a` — cells gcc itself rejects** (a static
initializer must be a constant expression). The first version of the harness
counted those as failures and reported "11 wrong"; they are neither failures
nor passes and are now printed as their own symbol so they cannot be read as
evidence in either direction. After the fix: **0 wrong of 59 measured.**

## Two things the ticket had wrong, found by enumerating rather than trusting it

1. **It says three consumer sites. There are four.** The binop arm
   (`"abc" == (void*)0`) is not in the ticket's table and carries the same +8
   keyed the same fragile way.
2. **The assign site is not C-only.** Its condition is
   `... and (CProgramMode or IsNodePChar(ASTLeft[node]))` — it also fires in
   **Pascal** for a PChar destination, so it could not simply be deleted. It is
   now `(not CProgramMode) and IsNodePChar(...)`, keeping the Pascal arm intact.

## The mechanism that works already existed

The call-argument path keys on **the lowered value's type** —
`IRTk[aval] = tyString` — not on the node kind. That is why the `arg` and
`direct` rows were green across all thirteen wrappers while the node-kind rows
were not: asking what a value *is* cannot be defeated by wrapping, and asking
what node produced it always can.

So the fix is not an invention. It is moving the decision to where the working
site already put it: **`AN_STR_LIT` lowers to `handle + 8` once, in the producer
arm of `IRLowerAST` under `CProgramMode`**, and the four consumer skips go away
(the Pascal half of the assign arm stays). The index arm's C base is now the
data pointer, so its `lo` adjustment drops from `-8` to `0`; Pascal keeps `-7`.

## Evidence — and the corpus was chosen differently this time

Earlier tonight I broke five gtk tests with a C-frontend change whose
differential I had selected by grepping **C sources**. The affected population
was `.pas` files, so no number of C cells could have seen it
(`bug-c-a-header-reached-by-uses-discards-function-bodies-and-imports-them-instead`,
reverted). The corpus here is chosen by **which paths reach the code**, not by
which language I was editing:

- **Pascal binaries: 233 of 233 byte-identical**, before vs after, over an even
  spread of the string-bearing Pascal corpus (20 dark — would not build either
  side, unchanged). Byte-identity, not output equality: `CProgramMode` is false
  for Pascal, so the emitted code must be *the same*, and that is the claim
  actually being made.
- **All five gtk tests green** — `test_c_gtk`, `-types`, `-window`, `-call`,
  `-gtk3_stock`. This is the population the last change broke, and it is now in
  the evidence rather than in the postmortem.
- **C tests: 144 measured, identical stdout and exit code; 0 changed.**
  Binaries all differ by design here, so binary equality is the wrong instrument
  and output equality is the right one — the opposite of the Pascal claim above,
  for the opposite reason.

  The 163 selected did **not** all produce signal, and the first pass reported
  "163/163 identical" without saying so: **37 failed to compile under BOTH
  compilers** (they need include roots my harness did not pass), which is
  agreement between two silences. Re-running those with
  `-Ilib/crtl/include -Ilib/crtl/src` recovered **18** into real cells — all
  identical — and **19 remain dark**, needing flags I did not supply. Those 19
  are not evidence in either direction and are not counted as passes. Same rule
  as the census's `n/a` cells and the same rule tstate applies to skipped jobs:
  *a skip scored passlike is invisible in the verdict.*
- A 17-line C string-operations probe against gcc: literal indexing, `sizeof`,
  `strlen`, `strcmp`, pointer arithmetic on a literal, literal tables, struct
  initialisers, `*"Z"`, iterating a literal — identical.
- The Pascal side against **FPC**: `PChar` assignment, `p[0]`, `s[1]`,
  `Length('...')`, `'xyz'[i]`, concatenation — identical.
- Self-host fixedpoint; `tools/gate.sh quick` GREEN.

## What is deliberately unchanged

The other `+8` adjustments in `ir.inc` are not this ticket's. The one at the
default-argument path carries a comment noting the adjustment is inline "at
fifteen sites in this file"; those are managed-string/PChar conversions keyed on
value types, a different concern with its own ticket
(`refactor-centralize-managed-string-pchar-conversion`). This ticket removes the
four keyed on `ASTKind = AN_STR_LIT`, which are the fragile ones, and leaves the
value-keyed ones alone because they are the design being converged on.

## Log
- 2026-08-30 — opened at HEAD, found live (not latent), fixed, resolved,
  commit PENDING-COMMIT.
- 2026-08-30 — resolved, commit 31a3e6172.
