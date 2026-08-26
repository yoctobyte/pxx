---
track: P
prio: 55
type: bug
blocked-by: []
summary: "`procedure F(p: PChar = '-')` is refused outright — \"a string literal cannot be the default for a non-string parameter\" — at EVERY literal length, so it is not the one-char-literal bug. FPC accepts it and passes a pointer to the NUL-terminated data. A defaulted PChar parameter is ordinary C-binding shape."
status: backlog
owner: unassigned
---

# `p: PChar = '-'` is refused as a parameter default

Found 2026-08-26 by Track P while fixing
`bug-single-char-literal-as-pchar-argument-segfaults` — varying the shape
across the whole "one-char literal in a PChar context" family turned up three
neighbours that are *length-independent*, i.e. genuinely different defects that
the one-char bug was merely standing next to. This is one of them.

## Repro

```pascal
program d;
procedure Deflt(p: PChar = '-');
begin Writeln(p); end;
begin Deflt; end.
```

| compiler | `= '-'` | `= '--'` |
| --- | --- | --- |
| `fpc -O- -Mobjfpc -Sh` | prints `-` | prints `--` |
| pxx (HEAD, 2026-08-26) | `error: a string literal cannot be the default for a non-string parameter` | same error |

**Both lengths are refused**, which is what separates this from the one-char
bug: nothing here depends on the literal being one character.

## Mechanism (unverified — the diagnostic's site is known, the fix is not)

The refusal is `compiler/pasparser_decl.inc:1762`. The default-value machinery
records a string default as `ProcParamDefaultIsStr` + a char-pool span
(`ProcParamDefaultSOff`/`SLen`), and `DefaultArgValueNode`
(`compiler/pasparser_call.inc`) rebuilds it as an `AN_STR_LIT` tagged with the
parameter's own string kind. A POINTER parameter has no string kind to tag it
with, so the arm was never written and the declaration is refused instead.

Likely shape of the fix: let a pointer-typed parameter take the string default,
rebuild it as an `AN_STR_LIT` tagged `tyString`, and let the existing
"auto const char* marshalling" in `IRLowerCallArg` apply the +8 length-prefix
skip — the same route a *written* `Deflt('-')` argument now takes since
`bug-single-char-literal-as-pchar-argument-segfaults`.

## Why it matters

A defaulted `PChar` parameter is ordinary C-binding shape (`nil`, `''`, a
separator). The failure is at least LOUD — a compile error, not a wrong value —
which is why this is prio 55 rather than 80.

## Gate

Track P: `make compiler/pascal26` (self-host fixedpoint) + a repro whose output
matches FPC at both literal lengths. Add the rows to
`test/test_char_literal_to_pchar_param.pas`, which already asserts the rest of
the family.
