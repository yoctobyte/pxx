---
prio: 40
type: bug
track: N
summary: "Five token-level scans locate a def/class BODY with an unbounded `while Tokens[j].Kind <> tkIndent` walk. Nothing makes them fail safe: with no INDENT they run on into the NEXT construct and attribute its body to this one. Latent today only because the lexer guarantees the INDENT exists."
status: done
owner: claude-AN
---

# def/class body scans run on when no `tkIndent` is found

- **Type:** bug (latent — defence in depth) — **Track N**
- **Filed:** 2026-08-04, from Track A+N overnight work on
  [[bug-nilpy-one-line-def-and-class-bodies-do-not-parse]].
- **Not currently reachable.** Filed because the failure mode it re-arms has
  already shipped once, and because the single thing preventing it is now
  load-bearing and undocumented as such.

## The shape

`a843c17d4` made one-line suites work by normalising them **in the lexer**: a
`def`/`class` logical line whose depth-0 `:` is followed by real code gets a
synthesised `NEWLINE INDENT ... DEDENT` (`compiler/pylexer.inc:1022-1036`,
`1108-1112`). Every token-level body scanner therefore always finds an INDENT,
and none of them had to change.

That is the right design. The consequence is that **the lexer rule is now the
sole guarantee** behind five scans that have no fallback of their own:

| site | scan | bounded by |
| --- | --- | --- |
| `pyparser.inc:17983` | `while (j < bodyEnd) and (Tokens[j].Kind <> tkIndent) do Inc(j);` | `bodyEnd` |
| `pyparser.inc:16749` | `while (k < TokCount) and (Tokens[k].Kind <> tkIndent) do Inc(k);` | **`TokCount` only** |
| `pyparser.inc:17052` | same | **`TokCount` only** |
| `pyparser.inc:17116` | same | **`TokCount` only** |
| `pyparser.inc:19629` | `while (j < MainProgramTokCount) and (Tokens[j].Kind <> tkIndent)` | `tkEOF` bail |

`16749`, `17052` and `17116` are three textual copies of one step-past-a-nested-def
walk (in `PyInferDefRetType` and `PyMethodReturnsSelf`); they must change
together or not at all.

When such a scan finds no INDENT it does not report anything — it silently lands
on some LATER construct's indent and the caller proceeds as if that were the
body. That is exactly the incident recorded at `pyparser.inc:18836-18843`:

> `class G(Exception): pass` has no INDENT of its own, so the scan ran on to the
> NEXT class's indent and registered THAT class's members against G — ... failed
> with "unresolved forward: G.create", the ctor having been attributed to the
> wrong class.

## Why the guarantee is thinner than it looks

The lexer only synthesises when **all three** hold (`pylexer.inc:701-705`):
`def`/`class` is the first token of the logical line, `parenDepth = 0`, and it is
the first depth-0 colon on that line. Any future narrowing of those conditions
re-arms all five scans at once, silently, with the symptom appearing in an
unrelated construct.

That is not hypothetical: the line-start clause was **wrong for an imported
module** until 2026-08-04. It asked `TokCount = 0` of the whole token stream,
but `PyLexAppend` lexes a `.py` module on top of the importing program's tokens,
so a one-line def on a module's first line was not recognised — and the symptom
was a parse error attributed to the importing file's line numbering. Fixed by
asking the question about this lex (`streamBase`), but it is a worked example of
the trigger conditions being subtly wrong while everything else stayed green.

## Producer/consumer divergence, currently inert

The lexer and the pre-passes disagree about what counts as a statement boundary:

- producer, `pylexer.inc:701-705`: `TokCount = streamBase` or previous token in
  `[tkNewline, tkIndent, tkDedent]`
- consumers, `pyparser.inc:15287`, `19646`, `19699`: `i = PyScanLo` or previous
  token in `[tkNewline, tkIndent, tkDedent, tkSemicolon]`

So a `def` after a `;` is a statement start to the consumers and not to the
lexer. No legal Python puts `def` there (a compound statement cannot follow `;`
on one line), so this is inert — but it is a real divergence between one
producer and three consumers of the same notion, and it should be one predicate.

Worth noting the shapes already agree conceptually: `PyScanLo` is the consumers'
"base of this scan", which is exactly what `streamBase` is for the lexer.

## Proposed fix

1. Make the three copies at `16749`/`17052`/`17116` one helper, and have it
   report "no INDENT found" rather than returning a run-on position.
2. At each of the five sites, stop the hunt at a `tkFunction`/`tkClass` or a
   second `tkNewline` as well, and when no INDENT was found **skip the harvest**
   instead of proceeding — an empty span is the correct answer for a body that
   has none, which is the same call `a0cf42cb6` made for the class case.
3. Fold the statement-boundary test into one shared predicate used by both the
   lexer rule and the pre-passes, so producer and consumers cannot drift.

Low priority deliberately: nothing is broken today. This is about making the
failure mode LOUD if the guarantee ever weakens, because its current symptom is
a wrong attribution reported far from the cause.

## Gate

`make test-nilpy` + self-host byte-identical. No behaviour change is expected,
so the test is the existing suite staying green plus the one-line suites
(`test_nilpy_one_line_def_suite.npy`, `test_nilpy_one_line_class_body.npy`,
`test_nilpy_one_line_def_in_module.npy`) continuing to pass.

## FIXED 2026-08-07 — parts 1 and 2 done, part 3 deliberately not

### What changed

Two new helpers in `pyparser.inc`, and all five sites now go through them:

- `PyFindSuiteIndent(start, limit)` — the INDENT opening the suite of the
  def/class at `start`, or **-1 when it has none**. Never walks past the end of
  that construct's HEADER: it stops at a second `tkNewline` (the first ends the
  header) or at another `tkFunction`/`tkClass`. This is the bound the ticket
  asked for, in one place.
- `PySkipNestedSuite(start)` — the position just past the matching DEDENT, or
  -1. Built on the above, and it replaces the **three textual copies** at the
  old `16749`/`17052`/`17116` (which had drifted to `18158`/`18488`/`18552`, and
  live in three functions, not two: `PyInferDefRetType`, `PyMethodReturnsSelf`
  and `PyDefHasValueReturn`).

Callers on the -1 path now stop instead of proceeding, which is the ticket's
point 2: the three return-type/self scans `Exit` with their conservative default
rather than advancing into a later construct and reading ITS returns as this
def's; `PyRegisterClassMembers` harvests **no** fields for a method with no
suite instead of the next method's; `PyDefBindsNameLocally` answers False.

### Part 3 (one shared statement-boundary predicate) NOT done

The producer/consumer divergence the ticket documents — `pylexer.inc`'s
`streamBase`-relative line-start test versus the pre-passes' `PyScanLo`-relative
one, differing by `tkSemicolon` — is real and still there. It is left alone
deliberately: it is inert (no legal Python puts `def` after `;`), and unifying a
predicate ACROSS the lexer/parser boundary is a behaviour-changing edit to the
one guarantee this whole ticket says is load-bearing. Doing it in the same
change that removes the scans' dependence on that guarantee would mean touching
both the safety net and the thing it protects against at once. Worth its own
ticket if anyone wants it; the scans no longer depend on it being right.

### Measured — behaviour-preserving, controlled against PINNED

No behaviour change is expected, so the evidence is that there is none. New test
`test/test_nilpy_body_scan_attribution.npy` — 9 lines, one section per affected
caller, in the shape nearest the hazard (one-line suites and nested defs packed
directly against their neighbours, so a run-on of even one construct changes an
answer):

| binary | result |
| --- | --- |
| CPython oracle | reference |
| **PINNED** (pre-change) | byte-identical |
| this change | byte-identical |

Identical on the pre-change binary is the point: it confirms the refactor
preserves attribution rather than merely agreeing with CPython for a new reason.
The three one-line suite tests the ticket names (`test_nilpy_one_line_def_suite`,
`test_nilpy_one_line_class_body`, `test_nilpy_one_line_def_in_module`) also pass.

### Gate

`make fpc-check` byte-identical (two routines added — the declaration-order
hazard), self-host fixedpoint, `tools/gate.sh quick`.

## Log
- 2026-08-07 — resolved, commit PENDING-COMMIT.
