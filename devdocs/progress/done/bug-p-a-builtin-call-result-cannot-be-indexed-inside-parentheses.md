---
track: P
prio: 40
type: bug
status: done
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

---

## 2026-09-01 (frankH) — the mechanism is confirmed by a control, and the list needs narrowing

**Your hypothesis is right and there is now a control for it.** The summary says
the `[` suffix is missing from the BUILTIN arm and that a user function indexes
fine. That is now measured with the builtin arm as the only variable: **the same
call flips from rejected to accepted purely by adding `uses sysutils`.**

| expression | no `uses sysutils` | `uses sysutils` |
| --- | --- | --- |
| `(ParamStr(1)[1] = '-')` | REJECTS | **REJECTS** |
| `(IntToStr(i)[1] = '1')` | REJECTS | PARSES |
| `(UpperCase(s)[1] = 'X')` | REJECTS | PARSES |
| `(Trim(s)[1] = 'x')` | REJECTS | PARSES |
| `(Concat(s,s)[1] = 'x')` | REJECTS | PARSES |
| `(Copy(s,1,2)[1] = 'x')` | PARSES | PARSES |

**So one row of the summary needs correcting:** *"ParamStr, IntToStr, UpperCase,
Trim and Concat all reject"* is true only without `uses sysutils`. Four of the
five stop rejecting the moment a real Pascal routine in `sysutils` shadows the
builtin and the call takes the identifier path. **`ParamStr` is the odd one and
the important one — it has no sysutils twin, so it rejects either way**, which
is exactly why `compiler/compiler.pas` is the site that had to be worked around
and not some other caller. `Copy` parses in both because it has its own node.

That narrows the fix: it is the builtin-call arm of the parenthesised path, and
`ParamStr` is the row to gate on, because it is the only one that cannot be
accidentally satisfied by a shadowing unit.

**Also: `compiler/compiler.pas:1841` was citing a slug that does not exist.**
The workaround comment there named
`bug-a-indexing-a-call-result-inside-parentheses-is-rejected`, which is in no
folder and never was — so the comment asserted the limitation was tracked while
nothing tracked it. Repointed at this ticket, which is the one you filed from
that same workaround. The technical claim in that comment was re-measured before
touching it and still holds; only the citation was false.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 06a2d7aa7.

---

## 2026-09-04 (frankA) — FIXED, and "inside parentheses" was never the boundary

**The summary's boundary is wrong and the ticket is two defects, one of which
nobody had seen.** Measured across four syntactic contexts:

| context | before |
| --- | --- |
| `cc := ParamStr(0)[1];` assignment RHS | **accepted — and silently wrong** |
| `cc := (ParamStr(0)[1]);` parenthesised | rejected |
| `WriteLn(ParamStr(0)[1]);` argument | rejected |
| `if ParamStr(0)[1] = c then` if-condition | rejected, `expected 'then' before '['` |

The `if` row settles it: **no parentheses anywhere, same refusal.** The axis is
assignment-RHS versus everything else, not parenthesisation.

**And the accepting row miscompiled.** `cc := ParamStr(0)[1]` stored the low
byte of the string POINTER — 46 read the ordinary way and 224 through the
subscript, in one program, a different wrong character on every run (ASLR).
`PXXDBG=a.ast` shows why: no AN_INDEX node in the tree at all. The subscript was
not misparsed, it was **discarded**.

### The mechanism, which is a second ticket's worth

The `tkArgStr` arm builds ParamStr's node and returns with `[` still in the
token stream — a probe confirmed it does so in BOTH contexts, so the arm is the
common cause and the difference is entirely downstream. An argument list has no
catch-all and refused; `ParseStatementAST`'s catch-all `else` skipped to the `;`
in silence. That catch-all also accepted `[1];`, `^;`, `.Foo;`, `);` and `,;` as
whole statements, and `ParamStr(0)[;` compiled clean.

Both fixed in `ff2495a55`:

- the catch-all reports `a statement cannot start with '<tok>'`;
- the `tkArgStr` arm routes a following `[` into `GenMakeStringValueIndex`, the
  helper the literal, user-function and `Copy` paths already end at — **not** a
  sixth hand-rolled walker.

**The catch-all's first run against real source found three dead statements in
shipped RTL** — orphaned argument tails of debug `WriteLn(` heads deleted in
`1f8bb3e75` (2026-07-27), sitting in `compiler/builtin/pylib.pas` for five
weeks, inert and invisible. Removed in the same commit.

### Corrections to this ticket's own body

- The 2026-09-01 note's *"four of the five stop rejecting the moment `uses
  sysutils` shadows the builtin"* is right, and its conclusion that **ParamStr
  is the row to gate on** was the useful part — `test/test_paramstr_index.pas`
  gates on exactly that, for exactly that reason.
- `compiler/compiler.pas:1841`'s workaround can now be written directly. Left
  as found: it is correct code and rewriting it is not this ticket's business.

All five contexts now match fpc 3.2.2, and the `.expected` IS fpc's own output.
Positive control: pinned rejects the test at line 26 and silently miscompiles
the assignment row.
