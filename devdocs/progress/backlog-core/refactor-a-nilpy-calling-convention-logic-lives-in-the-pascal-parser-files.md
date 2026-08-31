---
prio: 25
track: A
type: refactor
blocked-by: []
summary: "78 `isNilPy` branches sit inside the pasparser_*.inc set — NilPy language rules living in files named for the Pascal parser. It is why a Track N ticket routes its holder into files Track N does not own, and it is `the-substrate-is-ast-and-ir-not-the-parser` violated by filename rather than by design."
status: new
owner: ""
---

# NilPy calling-convention logic lives inside the Pascal parser files

- **Type:** refactor — filed 2026-08-30 by frankwasm, at the coordinator's
  request, out of
  [[bug-n-a-methods-keyword-call-drops-a-tuple-argument-when-an-earlier-default-is-skipped]].
- **Spans three lanes:** the files are Track P's, the rules encoded in them are
  Track N's, and a carve-out is Track A's integration call — which is why it is
  filed under A rather than under either frontend.

## The observation

That ticket was filed as Track N, against tkinter's `grid(padx=(8, 6))`. Its
defect turned out to live in `compiler/pasparser_call.inc` — a **Pascal**
frontend file — inside a branch that only ever runs for NilPy:

```pascal
      if isNilPy and (CurTok.Kind = tkIdent) and
         (TokPos < TokCount) and (Tokens[TokPos].Kind = tkAssign) then
```

Landing the fix needed an explicit cross-lane grant (`e268f9990`), because a
Track N holder does not own that file. **The grant was the right call; needing
one for a NilPy language rule is the smell.**

## How much of it there is — counted, not estimated

`isNilPy` occurrences across the `pasparser_*.inc` set at `bcb428ba25ac`:

| file | count |
| --- | --- |
| `pasparser_expr.inc` | 31 |
| `pasparser_lval.inc` | 20 |
| `pasparser_call.inc` | 8 |
| `pasparser_proc.inc` | 8 |
| `pasparser_name.inc` | 6 |
| `pasparser_stmt.inc` | 5 |
| **total** | **78** |

In `pasparser_call.inc` specifically: lines 613, 634, 1147, 1813, 1897, 1938,
2187 (plus one in a comment at 1413). Line numbers are post-`51b0753e7`, which
added a helper above most of them.

## Why it matters, and why it is not just tidiness

`devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md` is explicit:
**share the AST and the IR; duplicate the parser, the lexer and their support
functions per language.** A shared parser helper couples two specs and is wrong
in both. Here the coupling is not even shared *logic* — it is NilPy-only logic
sitting in a Pascal-named file, so the rule is being violated **by filename**
rather than by design.

The concrete costs, both already paid:

- **Routing.** A Track N ticket sends its holder into files Track N does not
  own. That is a grant, a collision check across every checkout, and a
  coordinator round-trip per ticket.
- **Gating.** The fix had to clear Track **A**'s gate, not N's, because the
  file is shared ground. The lane's own gate was not sufficient and the ticket's
  `Gate:` line said otherwise.

`parser.inc` was already sliced into the `pasparser_*` set for exactly this
family of reasons, and NilPy's forwards went to `pyforwards.inc` at the same
time (see the map at the bottom of `compiler/frontend_forwards.inc`). This is
the residue that slice did not reach.

## What this ticket is NOT asking for

Not a mechanical move. 78 branches is a carve-out question, not a one-line
relocation, and several of them are genuinely about *shared* machinery
answering a NilPy question rather than about NilPy code that wandered. The
honest first step is a survey that sorts them:

1. **NilPy-only logic** that should move to a NilPy-owned file;
2. **shared machinery** that legitimately takes a per-frontend answer, which
   should ask through a seam rather than branch inline;
3. **branches that exist only because the two frontends disagree about a
   default**, which may collapse entirely.

Only after that split is the size of the real job known. Whoever takes it
should read `devdocs/dev/normalise-dont-special-case.md` alongside the
substrate note — the second category is where a seam replaces a branch, and the
third is where cases get deleted rather than moved.

## Not urgent

Prio 25 deliberately. Nothing is broken by the current arrangement; it costs a
grant and a wider gate per ticket that lands in it. It becomes urgent only if
two lanes need the same `pasparser_*` file at once, which has not happened —
on the night this was filed, three lanes held three distinct files.
