---
prio: 40
type: bug
track: N
summary: "Five token-level scans locate a def/class BODY with an unbounded `while Tokens[j].Kind <> tkIndent` walk. Nothing makes them fail safe: with no INDENT they run on into the NEXT construct and attribute its body to this one. Latent today only because the lexer guarantees the INDENT exists."
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
