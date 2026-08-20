---
track: P
prio: 55
type: bug
blocked-by: []
summary: "`String(p)` on a PChar was a compile error while `AnsiString(p)`, the implicit `t := p` and `StrPas(p)` -- the same NUL-terminated-to-Pascal conversion, three other spellings -- all worked. `String` is a keyword token with its own parser branch, so it never reached the identifier-cast path."
status: done
owner: frank1-ACP
---

# `String(p)` on a PChar is rejected while `AnsiString(p)` works

- **Track P** (`compiler/parser.inc`, the `tkString_T` factor).
- Found 2026-08-20 by an FPC differential probe over pointers and PChar.

## The measurement

`fpc -O- -Mobjfpc` 3.2.2 vs pxx at `fe8a34230`, with `s := 'hello'` and
`p := PChar(s)`:

| expression | FPC | pxx |
| --- | --- | --- |
| `t := String(p)` | hello | **error: String(): operand must be Char or string** |
| `t := String(p + 2)` | llo | **same error** |
| `t := String(PChar(@buf[0]))` | abc | **same error** |
| `t := AnsiString(p)` | hello | hello |
| `t := p` | hello | hello |
| `t := StrPas(p)` | hello | hello |

One conversion, four spellings, and the broken one is the spelling real FPC
code writes.

## Root cause

`String` is a **keyword** (`tkString_T`) with its own factor branch, which
handled a string operand (passthrough), a Char operand (`AN_STR_FROM_CHAR`) and
a Variant operand (`VariantCastToTemp`), then errored. `AnsiString` is an
ordinary identifier and goes through the generic built-in-typecast path, which
builds an `AN_PTR_CAST` and works for any operand including a pointer — PChar
is `tyPointer` here.

So the two spellings of one cast were served by two entirely separate pieces of
code, and only one of them knew about pointers. That is the shape
`devdocs/dev/normalise-dont-special-case.md` describes, and the keyword/identifier
split is exactly why nobody noticed: the paths do not look like duplicates.

The fix gives the `tkString_T` branch the pointer arm, building the same
`AN_PTR_CAST` the identifier path builds, with the same managed-vs-frozen
choice of string kind (`PXX_MANAGED_STRING`).

## Test

`test/test_string_of_pchar.pas`, 17 FPC-verified rows: `String(p)`,
`String(p + 2)`, `String(PChar(@buf))`, assigned / concatenated / measured /
upper-cased; an empty C string; all four spellings compared against each other
in one row; and the operands `String()` already accepted (string, Char, Char
literal, Variant) so the fix is proved not to have moved them. The pinned
binary refuses the test outright.

## Also found by the same probe, and fixed alongside

`bug-p-inc-of-a-typed-pointer-steps-one-byte` — it only became visible once
this compile error was gone.

## Gate

`make compiler/pascal26` fixedpoint converged after 1 round; `tools/gate.sh
quick` GREEN.
