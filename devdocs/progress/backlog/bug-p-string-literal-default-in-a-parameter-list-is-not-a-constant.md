---
track: P
prio: 55
type: bug
summary: "A STRING literal as a parameter's default value (`s: AnsiString = 'a'`) is rejected with 'not a constant'. The storage (ProcParamDefaultIsStr/SOff/SLen) and the call-site rebuild both already exist and are used by NilPy — only the Pascal declaration parser never accepts the literal. Sibling of the float-literal case"
---

# `s: AnsiString = 'a'` is rejected as "not a constant"

- **Type:** bug (Pascal frontend — parameter default declarations)
- **Opened:** 2026-08-10
- **Found by:** Track A+C+P+N, sweeping the neighbouring shapes of
  [[bug-p-constructor-with-a-defaulted-variant-param-corrupts-memory]].

## Repro

```pascal
program n;
procedure P(s: AnsiString = 'a'; k: Integer = 2); begin end;
begin end.
```

```
pascal26:2: error: not a constant
  near: P  s  AnsiString  >>> a  k
```

## What narrows it

| shape | result |
| --- | --- |
| `s: AnsiString = 'a'` | **error: not a constant** |
| `s: AnsiString = 1` | ok (an integer default on a string param — accepted, and almost certainly wrong; see below) |
| `s: string = 'a'` | check this too — the frozen vs managed kinds take different paths downstream |

**The second row is the more interesting one.** An *integer* default on an
`AnsiString` parameter is accepted without complaint. Whether the callee then
sees a valid empty string or a bare ordinal reinterpreted as a string pointer
is untested — if the latter, that is a silent-wrong-value/corruption bug of the
same family as the parent ticket and this ticket should be split, with that arm
promoted. **Measure it before assuming.**

## Likely cause (unverified)

Same site and same shape as the float case
([[bug-p-float-literal-default-in-a-parameter-list-fails-to-parse]]): the
declaration parses its default through the `Int64` const folder (`ConstEval`,
`compiler/parser.inc`), which has no arm for a string literal and falls through
to its `Error('not a constant')`.

Downstream is already built: `ProcParamDefaultIsStr` / `ProcParamDefaultSOff` /
`ProcParamDefaultSLen` exist in `defs.inc`, and `DefaultArgValueNode`
(`parser.inc`) already rebuilds an `AN_STR_LIT` from them — including the
tyAnsiString-vs-tyString tagging that a previous NilPy bug
(`bug-nilpy-dataclass-str-field-default-is-dropped`) paid for. The Pascal
declaration parser simply never sets the flags.

Fix together with the float sibling: one concept (a non-ordinal literal
default), one missing mechanism.

## Gate

The repro compiling **and** a value check that the omitted argument arrives as
`'a'` — a frozen literal handed to a managed `AnsiString` parameter has
historically arrived as the EMPTY string while compiling perfectly, so a
parse-only test proves nothing. Extend
`test/test_default_params_methods.pas`. Then `tools/gate.sh quick`.
