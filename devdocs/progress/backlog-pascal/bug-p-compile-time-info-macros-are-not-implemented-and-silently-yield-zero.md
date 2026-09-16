---
slug: bug-p-compile-time-info-macros-are-not-implemented-and-silently-yield-zero
title: "`{$I %DATE%}` and the other compile-time info macros silently yield 0"
track: P
prio: 55
type: bug
status: open
owner: ""
found-by: franks-ee
created: 2026-09-16
tags: [directives, preprocessor, lexer, silent-wrong-value, fpc-corpus]
blocked-by: []
summary: "`const d = {$I %DATE%};` compiles with NO diagnostic and yields Integer 0; fpc yields the string '2026/09/16'. Same for %TIME%, %FPCVERSION%, %FILE%, %LINE% -- all 0. THE CAUSE IS A SEAM, NOT A MISSING FEATURE: the include pre-pass (ExpandIncludes, compiler/elfwriter.inc) explicitly RECOGNISES `{$I %...%}` and skips it with the comment `leave them in the text for the lexer`, and the lexer has no handler for it -- so each side is written as though the other does it, the brace is eaten as an unknown directive, and `const d = ;` becomes 0 instead of a syntax error. A false premise stated as fact in a comment, which is the one place nobody re-measures. This is the head of 132 of the 207 units of umbrella-pxx-compiles-fpc-itself, ARRIVING IN DISGUISE: it reports as `globals.pas:1095 no overload of Replace matches these arguments (AnsiString, ShortString, Integer)`, which reads like a library gap and is not one -- the candidates are the corpus's own cutils.pas:82-83 and the defect is the THIRD argument, `date_string`, declared `= {$I %DATE%}` in version.pas:41. Adding an RTL overload to make that call resolve would make a wrong program compile."
---

# `{$I %MACRO%}` is not implemented and fails silently as 0

## Repro

```pascal
program m;
const d = {$I %DATE%};
begin WriteLn('[', d, ']  SizeOf=', SizeOf(d)); end.
```

fpc: `[2026/09/16]  SizeOf=10`. pxx: `[0]  SizeOf=4`. No warning, no error.

## fpc 3.2.2's semantics, measured

Every row produced by compiling and running, not read from documentation:

| macro | fpc answers |
| --- | --- |
| `%DATE%` | `2026/09/16` |
| `%TIME%` | `16:08:36` |
| `%FPCVERSION%` | `3.2.2` |
| `%FPCTARGET%` | `x86_64` |
| `%FPCTARGETCPU%` | `x86_64` |
| `%FPCTARGETOS%` | `Linux` |
| `%FILE%` | the source file's basename |
| `%LINE%` | the line the directive sits on |
| anything else | the ENVIRONMENT VARIABLE of that name |
| an unset environment variable | `''`, plus `Warning: Include environment "X" not found in environment` |

All of them expand to a STRING literal, which is why `date_string` is a string
in fpc and an Integer here.

## The seam

`ExpandIncludes` in `compiler/elfwriter.inc` handles `{$I file}` by splicing the
file's text in. For `{$I %...%}` it takes a deliberate different arm:

```pascal
{ NOT an include: `{$I+}` / `{$I-}` IO-checking switches and
  `{$I %MACRO%}` compile-time info macros -- leave them in the text
  for the lexer (the hard miss-error below must not fire on them). }
```

The `{$I±}` half of that comment is true. The `%MACRO%` half is not: nothing in
`paslexer.inc` handles it. `ProcessPasDirective` has no arm for it, so the whole
`{...}` is consumed as an unrecognised directive and the const initialiser is
left empty.

**Two independent defects, and the second is the general one.** Even with the
macros unimplemented, `const d = ;` should not compile. It yields 0 — the
empty/default collision this project's own rules warn about, where "the
machinery did nothing" and "the answer is 0" are the same observation.

## Why it is not a small fix

The pre-pass is the right place (it already substitutes text, and substituting a
quoted literal is the same operation, with the cursor advance already written).
But `%DATE%`/`%TIME%` need a runtime clock **on both build paths**:

* under real FPC the compiler already imports `SysUtils`, so that arm is free;
* under self-host it needs a raw `clock_gettime`, and the syscall number is
  host-architecture-specific. `compiler/elfwriter.inc` already hardcodes x86-64
  numbers (217 for getdents64) with only a `CPU_WASM32` escape, so following
  that pattern would widen an existing latent portability assumption rather
  than add a new one — worth deciding rather than copying.

Plus civil-from-days arithmetic (the compiler has none: no `EncodeDate`, no
`1970` anywhere), a local-vs-UTC decision (fpc's `%DATE%` is local), and the
environment fallback — for which **the compiler has no `getenv` at all**.

## Suggested shape

Substitute in `ExpandIncludes`, emitting a quoted literal with `''` doubling.
Implement the macros that need no clock and no environment first
(`%FILE%`, `%LINE%`, and the target names from `TargetArchName`), and **error
loudly on every macro not implemented** rather than leaving any of them at 0 —
refusing a program fpc accepts is a smaller harm than compiling a different one,
and it is the half of this ticket that can land before the clock question is
settled.
