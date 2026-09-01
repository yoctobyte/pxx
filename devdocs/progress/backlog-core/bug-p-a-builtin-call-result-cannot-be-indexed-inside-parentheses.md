---
track: P
prio: 40
type: bug
status: open
found: 2026-09-01
found-by: frankA
owner: ""
blocked-by: []
summary: "`(IntToStr(i)[1] = '1')` is rejected as \"expected ')' before '['\" while the identical expression without the parentheses compiles and runs. The `[` suffix is missing from the BUILTIN-call arm of the parenthesised expression path only: a USER function's result indexes fine in every position tested, and `Copy(s,1,3)[1]` works because Copy has its own node. ParamStr, IntToStr, UpperCase, Trim and Concat all reject. FPC 3.2.2 accepts. Found while adding an argument guard to compiler.pas, where `(ParamStr(i+1)[1] = '-')` had to become a local variable to compile."
---

# A builtin call's result cannot be indexed inside parentheses

## Measured

One program per row, same compiler (`a2afed94f80f`), `b: Boolean; i: Integer;
s: AnsiString`:

| expression | pxx |
| --- | --- |
| `b := ParamStr(i)[1] = '-';` | **accepts** |
| `b := (ParamStr(i)[1] = '-');` | rejects |
| `WriteLn(ParamStr(i)[1]);` | rejects |
| `if (ParamCount >= 1) and (ParamStr(i)[1] = '-') then ...` | rejects |
| `b := (IntToStr(i)[1] = '1');` | rejects |
| `b := (UpperCase(s)[1] = 'A');` | rejects |
| `b := (Trim(s)[1] = 'a');` | rejects |
| `b := (Concat(s,s)[1] = 'a');` | rejects |
| `b := (Copy(s,1,3)[1] = 'a');` | **accepts** |

The diagnostic is `expected ')' before '['`, and the `near:` window points at
the `[`, so this is a parse gap and not a typing one.

**The control that names the arm:** a USER function with the identical
signature (`function F(n: Integer): AnsiString`) indexes correctly in ALL FOUR
positions above — bare, parenthesised, inside `WriteLn`, and inside an `and`.
So it is not "indexing a call result"; it is the BUILTIN-call arm specifically.
`Copy` passing corroborates it: Copy is lowered to its own AST node rather than
through the builtin-call path.

FPC 3.2.2 accepts every row, so this is a genuine gap and not a dialect choice.

## Why the parenthesised/unparenthesised split

`b := ParamStr(i)[1] = '-'` accepting while `b := (ParamStr(i)[1] = '-')`
rejects says the suffix loop that handles `[` after a builtin call runs on one
path into the expression parser and not on the other. That is the same
"six copies of the postfix walk, each accepting a different subset" shape as
[[refactor-a-the-pointer-suffix-walk-has-six-copies-in-the-pascal-frontend]]
and [[bug-a-a-comma-indexed-multi-dim-subscript-is-not-parsed-through-a-cast-or-call-result]]
— worth fixing with those rather than as a lone arm, and worth checking against
the same matrix.

## Where it cost something

`compiler/compiler.pas`'s new output-path guard wanted
`(Length(ParamStr(i + 1)) > 0) and (ParamStr(i + 1)[1] = '-')` and had to be
written through a local instead. The local is fine style here, so the workaround
is noted in place with a pointer to this ticket rather than left silent.
