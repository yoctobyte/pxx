---
slug: bug-n-adjacent-string-literals-splice-a-plus-so-a-tighter-operator-binds-wrong
title: adjacent string literals splice a `+`, so a tighter operator binds wrong
summary: >
  The lexer splices ` + ` between adjacent string literals, which is recorded as
  the design in `bug-nilpy-adjacent-string-literals-concatenate-in-only-some-positions`
  (done 2026-08-13, b516a818c). A spliced `+` is an ordinary binary operator, so
  any operator that binds TIGHTER than `+` — `*`, `%`, `/`, `**` — now takes only
  the LAST literal as its left operand. CPython concatenates adjacent literals at
  tokenisation, where nothing can get between them. `"x" "y" * 3` is `'xyyy'`
  here and `'xyxyxy'` in CPython, silently. Operators that bind LOOSER than `+`
  (`==`, `in`, `and`) are unaffected, which is why this survived the seven-row
  fixture that closed the earlier ticket.
track: N
type: bug
prio: 55
owner: unassigned
status: open
---

## How it was reached

lekkerzeilen `--open-water`, under `setarch -R`:
`TypeError: not all arguments converted during string formatting`, traced to
app.py:4033, which is the ordinary way a long message is wrapped:

```python
print("  controller: %s -- left stick helm, triggers ahead and "
      "astern" % self.pad.name)
```

Spliced, that is `"...and " + ("astern" % self.pad.name)` — a format with no
specifier and one argument, hence the TypeError. It only fires when a game
controller is plugged in, which is why the world path never reached it.

## Repro

```python
name = "PS4 pad"
print("a %s " "b" % name)      # CPython: 'a PS4 pad b'     pxx: TypeError
print("x" "y" * 3)             # CPython: 'xyxyxy'          pxx: 'xyyy'
print(2 * "x" "y")             # CPython: 'xyxy'            pxx: 'xxy'
print(repr("a" "b" * 0))       # CPython: ''                pxx: 'a'
print(("a %s " "b") % name)    # parenthesised: correct in both
print("a" "b" == "ab")         # True in both — `==` is looser than `+`
```

Measured at bccef26c7, compiler binary 2026-09-14 03:12, x86-64 `--threadsafe`.
Every wrong row above is SILENT except the `%` one.

## Mechanism, and why it is a consequence of the earlier fix

`bug-nilpy-adjacent-string-literals-concatenate-in-only-some-positions` closed
with, in its own words, "the NilPy lexer already splices ` + ` between adjacent
literals, so `"a" "b"` and `"a" + "b"` are the same construct by the time the
parser sees them". That equivalence is exactly the defect: in CPython they are
NOT the same construct. Literal concatenation happens in the tokeniser, so it is
tighter than every operator; `+` sits at additive precedence, below `* / % **`.

The rule is therefore: splicing is harmless where the neighbouring operator
binds looser than `+`, and wrong where it binds tighter. The three `*` rows and
the `%` row above are that, and I confirmed the mechanism by prediction before
measuring — `"x" "y" * 3` -> `'xyyy'`, `2 * "x" "y"` -> `'xxy'`,
`"a" "b" * 0` -> `'a'` were all predicted from "read it as a spliced `+`" and all
three came out exactly so.

That also explains the survival: the closing fixture covered seven POSITIONS
(assignment, pylib call, user def, list, dict, ...) and no row put an operator
after the pair. Position was swept; precedence was not.

## The fix

The earlier ticket's own "Where to look" already named it and the splice was
chosen instead:

> The fix is presumably to fold adjacent literals **in the string-literal factor
> itself** — one place, every position — rather than at whichever site currently
> handles it.

Folding in the literal factor produces ONE literal token and no operator, which
is what CPython does and what makes precedence a non-question. If the splice is
kept for other reasons, the minimum is to splice a PARENTHESISED group rather
than a bare `+`, so the pair binds as a unit.

Worth checking while in there: an f-string or a raw/bytes literal adjacent to a
plain one, and a three-or-more run (`"a" "b" "c" * 2`), which the splice would
get wrong in a second way.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` diffed against
CPython carrying the six rows above AND the seven position rows from the closed
ticket in the same file — the two fixtures are testing one construct and should
not drift apart again. Include at least one row per precedence class: tighter
than `+` (`*`, `%`, `**`), equal (`+`), looser (`==`, `in`).

## Log
- 2026-09-14 — filed from the lekkerzeilen `--open-water` wall. Reduction is
  single-file and inline above.
