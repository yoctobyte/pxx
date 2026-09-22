---
track: P
prio: 40
type: bug
status: open
found: 2026-09-22
found-by: frankb-8e
blocked-by: []
summary: "`procedure A;` with no body and no `forward` is ACCEPTED, and the next routine's body is parsed as A's -- so the parse runs off the end of the file and the error is reported in whatever unit the compiler appends next, naming a symbol that has nothing to do with it. Measured 2026-09-22 on a 12-line repro: the error is `undefined variable (UpperCase) in ./compiler/builtin/builtinheap.pas`. In a real build it cost an hour: one stray duplicated header line in compiler/emit.inc reported `undefined variable (LowerCase) in compiler/paslexer.inc` plus `nested routine token buffer overflow in compiler/rel8.inc`, three files away from the mistake and describing neither of the two things that were wrong. FPC refuses this outright with `Forward declaration not solved`. The small-file diagnostic DOES carry a good note (it names the appended unit and suggests an unterminated comment); the note is absent when the swallowing routine is in an .inc, which is the case that actually happens."
---

# A bodiless procedure declaration is accepted and swallows the next routine

## Repro, 12 lines

```pascal
program bodiless;

procedure A;            { declared, never defined, and NOT marked forward }

procedure B;
begin
  WriteLn(UpperCase('x'));
end;

begin
  B;
end.
```

```
pascal26:7: error: undefined variable (UpperCase)
  in: ./compiler/builtin/builtinheap.pas
  note: that unit is appended to every program by the compiler -- you did not write it.
```

FPC 3.2.2: `Forward declaration not solved: A`.

## Why it is worth fixing rather than deferring as "a differing diagnostic"

This is **not** us accepting more than FPC and being fine. The program is
ill-formed, we accept it, and the acceptance produces a **wrong parse**: `B`'s
body becomes `A`'s, `B` no longer exists, and the parse walks off the end of the
translation unit into whatever the compiler appends. Every error after that
point is reported against a file the author did not write, naming a symbol they
never mentioned.

## What it actually cost, 2026-09-22 (frankb-8e)

One editing slip in `compiler/emit.inc` — a procedure header emitted twice, so
the first copy had no body — produced:

```
pascal26:679: error: undefined variable (LowerCase)
  in: compiler/paslexer.inc
pascal26:71: error: nested routine token buffer overflow
  in: compiler/rel8.inc
```

Neither file was touched. Neither message describes either of the two real
facts (a duplicated header; a bodiless declaration). It took a five-step
bisection — stash-and-rebuild to confirm the change was the cause, then
splitting the addition into comment-only and code-only halves, both of which
passed on their own — to get back to a one-line edit. The bisection's own result
was *misleading in a second way*: "comment alone passes, code alone passes,
together they fail" reads as a size threshold and is not one. The two halves
passed because reconstructing them from the split files silently dropped the
duplicated line.

**The note that would have solved it exists and did not print.** With the
repro's small program the compiler says *"the parse ran off the end of
&lt;file&gt; -- an unterminated comment or string literal is the usual cause"*,
which is the right shape of hint. It is emitted only when the error lands in an
appended builtin unit; here it landed in an ordinary `.inc`, so nothing was
said.

## Two fixes, and the first is much cheaper than the second

1. **Refuse the declaration**, as FPC does: at the end of the enclosing scope,
   any routine declared without a body and without `forward` is an error naming
   **the declaration's own line**. This is the whole bug for the common case.
2. **Widen the run-off-the-end note** so it fires whenever the parse crosses out
   of the file the error's line number belongs to, not only when it reaches an
   appended builtin. That is the half that would have helped here.

Do 1 first; 2 is a separate improvement that helps every cause of a run-off, of
which this is only one.

## Not yet established

Whether `function` has the same shape, whether a bodiless declaration inside a
`class`/`object` declaration behaves differently, and whether `external`/
`cdecl`-imported routines take a different path that this must not disturb.
Each is one probe; none was run, because the ticket is filed from the
measurement that happened rather than from a survey.
