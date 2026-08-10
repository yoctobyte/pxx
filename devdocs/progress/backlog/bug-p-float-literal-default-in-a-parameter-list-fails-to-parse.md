---
track: P
prio: 55
type: bug
summary: "A FLOAT literal as a parameter's default value (`d: Double = 2.5`) does not parse — the const evaluator never consumes the token, so the error surfaces on the NEXT parameter (or the closing paren) as a bare 'unexpected token'. Integer defaults on the same Double parameter are fine, and the runtime machinery (ProcParamDefaultIsFloat) already exists"
---

# `d: Double = 2.5` fails to parse in a parameter list

- **Type:** bug (Pascal frontend — parameter default declarations)
- **Opened:** 2026-08-10
- **Found by:** Track A+C+P+N, while sweeping the neighbouring shapes of
  [[bug-p-constructor-with-a-defaulted-variant-param-corrupts-memory]] (that
  ticket's ctor path had silently dropped float/set/string defaults; testing
  whether they now work showed they cannot even be *declared*).

## Repro

```pascal
program n;
procedure P(d: Double = 2.5); begin end;
begin end.
```

```
pascal26:2: error: unexpected token
  near: P  d  Double  >>>
```

## What narrows it

| shape | result |
| --- | --- |
| `procedure P(d: Double = 2.5)` | **error** |
| `procedure P(d: Double = 2)` | ok (integer literal into a Double param) |
| `procedure P(d: Double = 2.5; s: Integer = 1)` | **error, reported at `s`** |
| `constructor C(d: Double = 2.5; ...)` | same error — not method-specific |

The misleading part is the *position*: with a following parameter the
diagnostic points at that parameter, not at the float. That reads as "the
second parameter is malformed" and sent the first investigation the wrong way.

## Likely cause (unverified — measure before writing this into a fix)

The declaration site parses the default through the **integer** const folder
(`ConstEval` / `ConstEvalTerm` in `compiler/parser.inc`, `Int64` throughout).
A float token matches none of its arms, so `r` is returned unchanged **and the
token is never consumed** — which is exactly why the failure surfaces one token
later rather than at the literal.

Note the *storage* is already there and is used by NilPy:
`ProcParamDefaultIsFloat` (`defs.inc`) documents "DefaultVal holds its IEEE 754
bits, as a float TOKEN does", and `DefaultArgValueNode` (`parser.inc`) already
rebuilds an `AN_FLOAT_LIT` from it. So this is a *declaration-side* gap only —
the Pascal parser never sets the flag. Sibling: the string-literal case,
[[bug-p-string-literal-default-in-a-parameter-list-is-not-a-constant]], which
fails in the same place with a different message.

Fix both together — they are one concept (a non-ordinal literal default) with
one missing mechanism, and fixing one arm alone is how the ctor path in the
parent ticket stayed broken.

## Gate

The repro compiling, plus a value check that the default actually arrives
(`P` called with no argument sees `2.5`, not `0`) — a parse-only test would
pass on a fix that records the wrong bits. Then `tools/gate.sh quick`.
Extend `test/test_default_params_methods.pas` rather than adding a new file.
