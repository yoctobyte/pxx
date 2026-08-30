---
slug: feature-c-diagnostics-name-the-module-they-are-in
track: C
prio: 40
type: feature
blocked-by: [bug-a-c-diagnostics-cannot-name-a-header-only-the-module-that-included-it]
summary: "A Pascal diagnostic now prints `in: <path>` when the error is in an include or a `uses`d unit. The C frontend has the same information already — CModRange* is populated in every build, not just under -g — and prints nothing, so an error in a crtl module or an included header still reports a bare line number."
status: unfinished
owner: frankC
---

# C diagnostics could name their module and do not

Fallout from `bug-a-a-parse-error-in-a-used-unit-reports-a-line-in-no-file`,
which gave the Pascal side an `in: <path>` context line under the diagnostic
whenever the offending token did not come from the main source.

The C frontend needs no new plumbing to do the same:

- `CModRange*` (defs.inc) already maps token index → the `.c` module, and is
  **explicitly not gated on `DebugInfo`** — the duplicate-definition check needs
  it in every build (`bug-c-static-functions-in-different-crtl-modules-collide`).
- `CModuleOfTok(t)` already reads it back, returning a `KeyStrs[]` index.
- `WriteDiagSourceFile` in `lexer.inc` is the single place that decides what to
  print; today it consults only the Pascal table and so says nothing for C.

So the shape is: when the Pascal table has no answer, ask the C one. Two
details to get right rather than assume:

1. **Headers vs modules.** `CModRange*` deliberately attributes a static defined
   in a header to the module that *included* it — which is right for the
   duplicate check and possibly wrong for an error message, where the user wants
   the header. The preprocessor's own `# <line> "<path>"` markers carry the
   header path; `CPPathAtDepth` may already have what is wanted.
2. **The main `.c` must stay silent**, exactly as the main `.pas` does — the user
   typed that name.

## Gate

An error in an included header, and one in a second `.c` module, each name the
file they are in; an error in the main `.c` prints no `in:` line. Self-host
byte-identical. The Pascal rows in `test-core` (`test_incdiag_*`) must stay green
— they assert that a Pascal main source prints no `in:` line, which is the same
rule.

## Landed: the module half. Parked: the header half. frankC, 2026-08-30

Under the bounded `WriteDiagSourceFile` grant (`715a2e1b3`). Two of the three
gate cases are met and the third is a Track A table, not a printer.

| case | before | now |
| --- | --- | --- |
| error in a pulled crtl module | silent | `in: ./compiler/../lib/crtl/src/string.c` |
| error in the main `.c` | silent | silent (unchanged, and now asserted) |
| error inside an included header | silent | **still silent** — `bug-a-c-diagnostics-cannot-name-a-header-only-the-module-that-included-it` |

### The grant's condition, met by construction

The C answer is an **appended `else if path = ''` arm**. The existing branch is
not touched, so every state that printed something still prints exactly that,
and every state that stayed silent *because the path was the main source* still
does — the fallback cannot fire one state early, because it fires only where the
Pascal table has no answer **at all**. Restructuring the condition instead would
have been invisible to all three `test_incdiag_*` rows, which have answers and
never reach the arm. (They were run and pass; so does the whole set at
`1154be46da74`.)

### What the measurement changed

`PXXDBG=c.srcmap`, the twin of `a.srcmap`, added in the same change for the same
reason: the C arm is invisible to every diagnostic the Pascal table answers, so
when it is wrong there is no output to be suspicious of.

1. **The ticket's detail 1 resolved the other way than expected.** It asks
   whether `CPPathAtDepth` or the `# <line> "<path>"` markers carry the header
   path. They do — and it does not help, because the marker handler *has* the
   header path and throws it away: `CMarkTokModule` takes `.c` only, and the
   header-accurate `DbgMarkTokFile` returns early without `-g`. The gap is a
   missing ungated table, `PasMarkTokFile`'s twin. Filed as A.

2. **A stale comment, found by measuring it.** `cpreproc.inc`'s header said the
   line markers are emitted *"Only under -g"*. `CPSyncLine` twenty lines below
   says the opposite and is right — they have been ungated since the crtl static
   fix. Corrected, with what *is* still gated spelled out.

3. **A diagnostic that names a Pascal builtin during a C compile.** `int main(void) { return 1;`
   with no closing brace prints `in: ./compiler/builtin/builtinheap.pas`. Not
   this change and not the fallback (the Pascal table answers, so the C arm never
   runs): `PXXDBG=a.srcmap` shows the C source is tokens 0..8, the builtin units
   are appended from 9 on, and the unterminated construct parks `TokPos` at
   exactly 9 — the C parser reads past the end of its own token stream into
   appended Pascal. Filed separately rather than papered over here.

4. **The `<crtl-prototype-pull>` guard is defensive and unreached.** Every error
   I could construct inside the pulled block reports `cmod=-1`, because the real
   `.c` markers inside it refine the synthetic one immediately. Kept, and
   labelled as untested in the code rather than left looking covered.

### Tests, validated in both directions where that means anything

`cdiag_module` and `cdiag_main` in `test-core`. The module row **fails on
`pinned` (53800fbeb0b6) and passes at `1154be46da74`** — a real before/after.
The main-source row passes on both and is a **guard, not a proof**: it exists so
that the day the module ranges stop returning to the main source, the user is
not told their own file is somewhere else. The module row asserts the *shape*
`lib/crtl/src/*.c` rather than which module defines `memchr`, so it is not
coupled to crtl's internals; if the trigger ever stops erroring, the row fails
loudly (no `in:` line) rather than passing vacuously.

## Correctness condition on the `lexer.inc` change (extracted 2026-08-30)

This lived in a *grant* ticket, which is why it is being moved rather than lost:
the grant mechanism was cut with the rest of the reservation system, but this half
of that ticket was never about permission.

**The Pascal arm of `WriteDiagSourceFile` must stay reachable in exactly the
states it was before.** The C answer is consulted only where the Pascal table
returns nothing, so it is not enough that Pascal diagnostics still work — a
fallback that fires **one state too early** is invisible to every Pascal test that
has an answer, because those tests only check that the answer is right, never that
it came from the Pascal path. Establish the reachability, don't infer it from a
green suite.

`lexer.inc` is still shared A/P ground — the one file Track P did not get when
`parser.inc` was sliced into `pasparser_*`. Under the current rules that is a
reason to say what you are touching and to keep the change to
`WriteDiagSourceFile`, not a reason to ask.
