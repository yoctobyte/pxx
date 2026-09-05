---
track: P
prio: 30
type: bug
blocked-by: []
summary: "FIXED. Both diagnostics now name a place the reader can act on. `unterminated comment` keeps the OUTER brace's line (it is the genuinely unclosed one) and adds notes naming every nested open-brace inside it — the offender is in that list. And a diagnostic landing inside an appended builtin unit now says that unit is the compiler's, that the mistake is at or before the last line of the file you named, and that an unterminated comment or string is the usual cause. Two must-not-compile fixtures assert the NOTE text, not the exit code."
status: done
owner: frankA
---

# A brace in comment prose reports the wrong line, and sometimes the wrong file

- **Type:** bug — **Track P** (Pascal dialect). The scanning lives in the
  **shared `lexer.inc`**, which P has not carved out, so this obeys A's
  no-concurrent-edit rule.
- **Filed:** 2026-08-30 by frankB, after it cost four compiles while writing
  `lib/rtl/mimic_string.pas`'s `Template` (`feature-lib-mimic-string-template`).
- Measured against **pin v395** (`aa78a7faf63a`).

## This is a LOCATION defect, not a message-wording one

CLAUDE.md defers diagnostic work whose subject is *"our diagnostic/message/error
number differs"* — that rule is about **parity with FPC's wording**, and this
ticket is not asking for different words. Both diagnostics below name a
**place**, and the place is wrong: in one case by 42 lines, in the other by an
entire file, into the stable RTL. A wrong location is the failure shape this
repo's debugging doctrine is built around — *the expensive bugs produce a
plausible wrong answer far from the cause* — here occurring in the instrument
itself.

## The property behind both

`{ }` comments **nest**, and a quote does **not** protect a brace inside one.
So a brace written as ordinary prose inside a comment is scanner input:

- an unmatched `{` opens a nested comment that the outer terminator then only
  half-closes;
- a `}` — including one inside `'...'` — **ends the comment early**, and the
  remaining prose becomes code.

A comment about brace-using syntax is a shape people will keep writing:
`${who}`, a JSON snippet, a C block, an f-string.

## Repro 1 — unmatched `{`: reported line is the comment's OPENING, not the offender

`a3.pas`, 13 lines. The comment opens on **line 2**; the offending `` `${who` ``
is on **line 7**:

```pascal
program a3;
{ line 2: this doc comment OPENS here and is otherwise fine.
  line 3
  line 4
  line 5
  line 6
  line 7: an unterminated placeholder is written `${who` in prose. <-- OFFENDER
  line 8
  line 9
  line 10 }
begin
  WriteLn('never reached');
end.
```

```
pascal26:2: error: unterminated comment
```

**Line 2, not line 7.** The report names where the *outer* comment began, which
is the one place guaranteed not to be the problem — it is the line the author
wrote correctly. In the real file that gap was **42 lines** (comment opened at
45, offending brace at 87), which is why it took four compiles: each fix
attempt was aimed at the reported line.

Note the balanced case is silent and correct: a comment containing `${who}` —
brace matched — compiles fine, because the nested comment opens and closes. So
the failure only appears for an *unmatched* brace, which is exactly the case an
author is least likely to notice.

## Repro 2 — `'}'` inside a comment: reported file is `builtinheap.pas`

`b2.pas`, **5 lines**, offending character on **line 3**:

```pascal
program b2;
begin
  { the loop below steps past the '}' terminator }
  WriteLn('ok');
end.
```

```
pascal26:35: error: undefined variable (interface)
  in: ./stable_linux_amd64/default/builtin/builtinheap.pas
  near: ok );
end.
 unit builtinheap  interface >>> type PVarRecInt64
```

**The user's file is not named at all.** The comment ends at the `}` inside the
quotes, ` terminator }` becomes code, and the parse derails far enough that the
first thing that fails is a declaration inside the compiler's own builtin heap
unit — a file the author never opened. The control (same comment, "closing
brace" spelled in words) compiles clean.

This is the worse of the two: a wrong line number is a slow read, a wrong file
in the stable RTL invites the reader to go looking for a compiler bug.

## What a fix should probably do

Not necessarily change the nesting rule — nested comments are a legitimate
dialect choice and changing it is a compatibility decision, not a bug fix.
The cheap correctness win is **location**:

- report `unterminated comment` at the **innermost unclosed** open-brace, not
  the outermost; and say the nesting depth, since "unterminated" reads as "you
  forgot a `}`" when the truth is "you accidentally wrote an extra `{`";
- when the parse derails into a *different file* from the one being compiled,
  say so — a diagnostic naming a stable-RTL file for a five-line user program
  is almost always a symptom of an earlier lexical error in the user's file,
  and naming that is more useful than the derailed parse's first casualty.

If the nesting rule itself is up for discussion that is a **Track U** question
(`decide-*`), not this ticket.

## Note

Recorded in `feature-lib-mimic-string-template`'s write-up as well, so the next
person writing a `mimic_` shim about brace-using syntax meets the note before
the bug. The workaround there was to spell braces in words inside comments.

## Resolution (2026-09-05, frankA)

Both halves fixed. The nesting RULE is untouched — that stays a Track U
question, as this ticket already said.

### Repro 1: the notes carry the offender, the headline keeps the outer line

The ticket asked for the **innermost unclosed** open-brace. That is wrong for
this repro, and working it out is the whole finding: in repro 1 the innermost
unclosed brace **is the outer one on line 2**. The author's `}` on line 10 did
close a comment — it closed the NESTED one that `` `${who `` opened. So
"innermost unclosed" would print exactly the line the ticket complains about.

What the reader actually needs is not one line but the SET: `compiler/paslexer.inc`
now records the line of every nested open-brace inside the comment (up to
`MAX_COMMENT_NEST_REPORTED = 32`, in `compiler/defs.inc`) and lists them as
notes. The headline stays at the outer brace because that is the only line the
scanner can truthfully call unterminated:

```
pascal26:17: error: unterminated comment
  note: brace comments NEST, and a quote does not protect a brace inside one.
  note: an open-brace inside this comment opened a nested one, so the closing brace
        balanced THAT instead. Look at line:
          22
```

The nesting property is stated in the note, because "unterminated" reads as
"you forgot a `}`" when the truth is "you wrote an extra `{`" — the ticket's
own observation.

### Repro 2: the derailed parse says whose file that is

`compiler/lexer.inc` gains `PathIsAppendedBuiltin`, and the `in:` arm of
`ErrorPrintAt` adds a note when the path is an appended builtin. Established
first with `PXXDBG='a.srcmap:*'`: builtin units are lexed into the SAME token
array as the main source, appended after it with no boundary, so a parse that
overruns the user's file reports **truthfully** at coordinates inside a file the
author never opened. Nothing is lying; the coordinates are real and belong to
somebody else's file.

```
  in: ./compiler/builtin/builtinheap.pas
  note: that unit is appended to every program by the compiler -- you did not write it.
        Either the parse ran off the end of <yourfile> (an unterminated comment or
        string literal is the usual cause), or this is a compiler bug. Check the
        first: the mistake would be at or before that file's last line.
```

### Fixtures, and why they assert the message

- `test/test_unterminated_comment_names_the_nested_brace.pas`
- `test/test_a_derailed_parse_names_the_appended_unit_as_the_compilers.pas`

Both are must-not-compile, and both are asserted on the **note text, never the
exit code**. Both files have always been refused — the entire defect was that
the refusal pointed somewhere useless — so an exit-code row scores a pass on
the bug itself. The Makefile rows grep for the wording AND for the offender's
line number (` 22`), plus a negative control: the nested-brace log must NOT
carry the appended-unit note, so the note is scoped to the builtins rather than
fired on every `in:` line.

Controls run by hand as well: a genuinely unterminated outer comment with no
nesting inside gets no notes; a balanced `${who}` still compiles; an error in a
real `uses`d unit prints `in: myunit.pas` with no note.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 310a8fa33.
