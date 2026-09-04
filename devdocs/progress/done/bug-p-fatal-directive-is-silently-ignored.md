---
track: P
prio: 35
type: bug
blocked-by: []
summary: "{$FATAL text} and {$MESSAGE FATAL text} are silently ignored: the frontend handles warning/message/error and treats every other directive as a no-op, so a guard block that means 'stop, this configuration is unsupported' compiles clean and produces a binary that should not exist."
status: done
owner: frankS
---

# `{$FATAL}` is silently ignored, so a guard that means "stop" does not

- **Type:** bug — Track P (Pascal frontend, `compiler/lexer.inc`).
- Found 2026-08-28 while writing `lib/rtl/signals.pas`, which needed a
  compile-time refusal on non-x86-64 targets. `{$ERROR}` was tried second and
  worked; `{$FATAL}` was tried first and compiled clean.

## Measured

`compiler/lexer.inc:1971-1976` dispatches exactly three message directives:

```pascal
else if CaseEqual(command, 'warning') then WarnAt(SrcLine, messageText)
else if CaseEqual(command, 'message') then writeln('pascal26:', SrcLine, ': message: ', messageText)
else if CaseEqual(command, 'error')   then Error(messageText)
```

`fatal` is not among them, and an unrecognised directive is a no-op. Repro:

```pascal
program e2;
{$fatal nope}
begin end.
```

compiles with `ok: e2 [code=61605B ...]` and exit 0. The `{$MESSAGE FATAL text}`
spelling is affected the same way for a different reason: it matches the
`message` arm, so it prints `message: FATAL text` and carries on.

## Why this is a bug and not a diagnostic-parity nit

CLAUDE.md's compat table defers "our diagnostic differs" and promotes "an
ignored directive producing wrong values" to a real bug. This is the second
shape, one step further along: the directive's entire purpose is to STOP the
compile, so ignoring it does not change a message — it changes whether an
artifact exists. A source file whose author wrote "this configuration is
unsupported, do not build" gets built, silently, and the wrongness shows up
wherever that binary is eventually run.

That is exactly the failure mode `lib/rtl/signals.pas` was guarding against: it
needs `__pxxSigNum`, which is x86-64 only, and answering anything on another
target would route every signal to handler 0.

## Fix sketch

One arm beside `error`, since `Error()` already exists and already halts:

```pascal
else if CaseEqual(command, 'fatal') then Error(messageText)
```

`fatal` also needs adding to the `messageText` capture condition at
`lexer.inc:1697` (currently `warning`/`message`/`error`), or the text will be
dropped and the diagnostic will be empty.

Worth deciding at the same time, rather than guessing: whether the
`{$MESSAGE FATAL text}` / `{$MESSAGE ERROR text}` forms should route by their
first word instead of printing it. FPC supports both spellings. If that is
wanted it is a slightly larger change to the `message` arm, and it is the
spelling real Delphi-flavoured source is more likely to use.

## Not investigated

Whether any other FPC directive in this family is silently swallowed — the
handler is an if/else chain with no "unknown directive" diagnostic, so the same
shape could hide more. A sweep would be a cheap follow-up and is the reason this
ticket does not simply say "add one line".

## Gate

Track P's: build the compiler, plus a repro asserting that a source containing
`{$FATAL}` fails to compile and that its message reaches stderr. The negative
control matters here — assert the failure, not merely that the compile stopped.

## Fixed 2026-09-04 (frankS, Track P)

`{$FATAL text}` and `{$STOP text}` now halt through `ErrorAt`, and
`{$MESSAGE FATAL text}` routes by its first word instead of printing it. Both
spellings measured before the fix on this tree: `{$fatal nope}` gave
`ok: d1 [...]` exit 0, `{$message fatal nope}` gave
`pascal26:1: message: fatal nope` exit 0.

Three things the sketch in this ticket did not have:

- **`fatal`/`stop`/`hint`/`note`/`info` joined the `messageText` CAPTURE**, which
  is the trap the ticket flagged: the text is captured in exactly one place and
  an arm added without its name there diagnoses with an empty message.
- **`{$MESSAGE <severity>}` routing is its own function** (`PasMessageSeverity`),
  because the answer to the ticket's open question is "yes, route it" and the
  five severities are one list, not five arms. A first word that is NOT one of
  the five stays part of the message — asserted, since that is the row that
  would silently change `{$MESSAGE error in config}`.
- **`ErrorAt(SrcLine, ...)`, not `Error(...)`.** `Error` prints `CurTok.Line`,
  which during the lex pass is the last token BEFORE the directive: `{$error}`
  on line 3 reported line 1, and these guards are written at the top of a file
  where that is most misleading. The existing `{$ERROR}` arm had the same defect
  and is fixed with it.

Quoted message text (`{$message fatal 'stop right here'}`) has its delimiters
stripped, and a trailing separator the capture used to append is trimmed —
`{$fatal nope}` said `error: nope ` before.

Tests: `test/test_pascal_fatal_directive.pas`,
`test_pascal_message_fatal_directive.pas`, `test_pascal_message_severities.pas`,
all wired into `test-core`, each asserting the FAILURE and the text rather than
the absence of a binary. The line number is asserted too, including on the
pre-existing `{$ERROR}` test.

The ticket's "not investigated" tail is
`bug-p-an-unknown-compiler-directive-is-silently-ignored`, fixed in the same
commit — that one is the generator, this was one of its outputs.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
