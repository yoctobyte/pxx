---
track: P
prio: 60
type: bug
blocked-by: []
status: backlog
owner: ""
summary: "`i := s` with i an Integer and s an AnsiString compiles clean and prints a heap address; `s := i` compiles clean and SEGFAULTS. Seventeen assignments fpc 3.2.2 rejects with `Incompatible types` are all accepted silently — record to integer, class to integer, string to boolean, every direction. This is not dialect laxness: it is a missing check that turns a one-character typo into a wrong value or a crash with no diagnostic anywhere."
---

# An assignment between incompatible types is not checked at all

Found 2026-08-24 while measuring how many errors one compile reports
([[feature-a-error-does-not-halt-so-a-parse-can-be-speculative]]). The
error-count measurement turned up something worse than the thing being measured.

## Measured

Harness (fpc 3.2.2 `-Mobjfpc`, warnings off, vs `compiler/pascal26` at
7fcf3108b):

```pascal
type TRec = record a: Integer; b: AnsiString; end;
     TCls = class x: Integer; end;
var r: TRec; c: TCls; i: Integer; s: AnsiString;
    d: Double; b: Boolean; p: Pointer; ch: Char;
```

| assignment | fpc 3.2.2 | pxx |
| --- | --- | --- |
| `i := s` | `Incompatible types: got "AnsiString" expected "LongInt"` | **accepted** |
| `s := i` | rejected | **accepted** |
| `i := r` / `r := i` | rejected | **accepted** |
| `i := c` / `c := i` | rejected | **accepted** |
| `i := 'text'` | rejected | **accepted** |
| `b := s` / `s := b` | rejected | **accepted** |
| `d := s` | rejected | **accepted** |
| `p := i` / `i := p` | rejected | **accepted** |
| `ch := s` | rejected | **accepted** |
| `s := r` | rejected | **accepted** |
| `b := i` / `i := b` | rejected | **accepted** |
| `i := d` | rejected | **accepted** |
| `d := i` | **accepted** (widening) | accepted |

Seventeen of eighteen. The one FPC accepts is the one that is actually legal.

## Why this is a bug and not the dialect being lax

CLAUDE.md says pxx's dialect is deliberately lax by default and that FPC-parity
strictness lives behind per-feature strict flags. That rule is about
*restrictions that were historic rather than necessary* — accepting something
FPC rejects for no good reason. It does not cover this, by the escape rule in
the same paragraph: **a finding that means silent wrong behaviour is a normal
bug, not a compat item.** These are silent wrong behaviour.

```pascal
s := 'hello';
i := s;        WriteLn(i);   { prints -1411383264 — the string HANDLE }
i := 7;
s := i;        WriteLn(s);   { SEGFAULT — 7 is dereferenced as a string handle }
```

No diagnostic, at any stage, for either. The second one is a crash produced by
code the compiler said was fine.

## Where it should live

The check belongs at the one place every assignment already funnels through, not
per statement form — `GenMakeAssign` is the obvious candidate, and putting it
anywhere else guarantees the second path stays unchecked
(`devdocs/dev/normalise-dont-special-case.md`). Note that a `for` loop variable,
a `+=`, an out-param clear and a record-field store all reach the same node, so
one check covers all of them; that is the argument for doing it there rather
than in `ParseStatementAST`.

## What must NOT start failing

The dialect deliberately allows conversions FPC does not, and the point of doing
this carefully is that the check must be a *whitelist of what is legal*, not a
blacklist of what is not. At minimum, before touching anything: Variant in both
directions (a Variant assigns to and from everything by design), the
Char/AnsiChar and string-family widenings, `PChar`/`^Char`/array-of-Char
interchange (see the `IsNodePChar` normalisation), enum-to-ordinal, a class to
its ancestor, an interface from a class implementing it, and every numeric
widening. `make test` and the demos are the real specification here, and this
change will find code in `lib/**` and `examples/**` that relies on laxness — that
discovery IS part of the ticket, and any such site is a Track B ticket, not a
reason to weaken the check.

Landing it behind `--strict-assign` first, defaulting off, and reading what the
full corpus says before flipping the default, is the low-risk sequencing.

## Gate

Track P's, plus a `{%FAIL}`-shaped test asserting each row of the table above is
refused with the line named, and one asserting the legal conversions listed
under "What must NOT start failing" still compile. The two runtime rows
(`i := s` printing a handle, `s := i` segfaulting) are the ones that make the
case; keep them in the ticket even after they stop compiling.
