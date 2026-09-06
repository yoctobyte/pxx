---
slug: bug-p-read-write-exit-and-halt-cannot-be-declared-as-user-routines
title: "DONE — read/write/readln/writeln declarable, and `exit := x` inside a function named `exit`"
track: P
prio: 40
type: bug
status: done
owner: "frankS"
blocked-by: []
summary: "ALL OF IT IS DONE (2026-09-06, frankS), IN TWO COMMITS, AND THIS TICKET'S ENUMERATION HAD TWO WRONG ROWS. (1) read/write/readln/writeln are declarable as user routines, top level and nested, with the calls reaching them -- 1ead40679, by a shadow predicate and a token rewrite rather than a lexer conversion. (2) The residual this ticket was rescoped to -- `exit := x > 0` inside `function exit(...)` -- is fixed too, and it is FOUR names not two: exit, halt, break and continue all have a bare-statement arm in ParseStatementAST and all four took the name, consumed it, produced their node, and left the `:=` for the caller. THE PREDICATE THAT LOOKS RIGHT IS THE WRONG ONE AND IT IS ONE NAME AWAY: OwnNameResultSym answers about a READ and carries `if DelphiMode then Exit` -- correct, a bare own-name read in Delphi is a reference to the routine -- but a WRITE is the Result synonym in Delphi too, and fpc 3.2.2 -Mdelphi compiles and runs it. The write condition already existed inline in two places and is now OwnNameLValueHere with three callers. THE TWO WRONG ROWS: `writeln` was never a parity row (fpc ACCEPTS the declaration; what it refuses is this ticket's probe BODY, where the console writeln after the shadowing declaration is an ARGUMENT-TYPE error at the CALL, because FPC shadowing is TOTAL -- and a row where both sides refuse for DIFFERENT reasons at DIFFERENT positions is not parity, it only reads that way because refused is the same string on both sides), and `exit`/`halt` DECLARE fine and always did, which the nested probe isolates and paslexer.inc confirms with zero matches for either spelling. Both errors came from ONE probe body that called an intrinsic after shadowing its name, so every row measured the CALL as well as the DECLARATION and could not say which had failed. Tests: test_a_global_routine_may_be_named_read_or_write.pas, test_a_soft_keyword_name_can_be_a_function_result.pas, test_a_soft_keyword_statement_still_works.pas -- the last one in its own file BECAUSE it has to be: once these names are declared, shadowing is total and pxx and fpc refuse the bare statements at the same line, so a control for them cannot live beside the declarations."
---

# `read`, `write`, `readln`, `exit`, `halt` cannot be declared as user routines

- **Type:** bug (Pascal frontend — these names are reserved where FPC's are not)
- **Track:** P — the lexer/declaration path
- **Found:** 2026-09-06, attempting [[feature-embed-pascal-script]]

## Repro

```pascal
program sh;
function read(x: LongInt): Boolean;
begin read := x > 0; end;
begin if read(1) then writeln('ok'); end.
```

`fpc 3.2.2 -Mobjfpc` prints `ok`. pxx: `pascal26:2: error: expected name`.

Nested is the same shape and the same defect:
`pascal26:3: error: nested routine: expected name`.

## The set, enumerated over 18 builtin names

| name | pxx | fpc |
| --- | --- | --- |
| `read` `write` `readln` `exit` `halt` | **refused** | accepted |
| `writeln` | refused | **also refused** — this row is PARITY |
| `str` `val` `new` `dispose` `length` `pos` `copy` `insert` `delete` `abs` `ord` `chr` `inc` `dec` | accepted | accepted |

**The `writeln` row is the control.** It is the reason this ticket does not say
"builtins are reserved and should not be": one of the six is a divergence-free
row, so a fix that simply un-reserves the lot would break parity rather than
restore it.

## Why it is not a one-line fix

`read` and `write` are lexed as keywords because the statement forms need
syntax no ordinary call has — `write(x:8:2)`, the file-handle first argument.
The fix is to make them **context-sensitive**: a user declaration of the name
shadows the builtin for that scope, which is what FPC does. That is a change to
declaration parsing and name resolution, not to a reserved-word list, and it
wants its own gate — hence filed rather than fixed in passing.

## Done when

The repro compiles and prints `ok`, `write(x:8:2)` still formats, `exit` with no
user declaration still exits, and `function writeln(...)` is still refused.

## 2026-09-06 (frankS) — the four names are done, and this ticket's table had two wrong rows

Landed with a **shadow predicate plus a token rewrite**, not a lexer conversion:
`IntrinsicNamesGlobalRoutineHere` (pasparser_call.inc), the global sibling of the
method predicate that was already there, asked at ParseFactorCore's entry and
before ParseStatementAST's dispatch. `IsMemberNameKind` gained an index-addressed
twin so the declaration sites stop hand-writing the token set.

**Why that route matters for the block on
[[bug-p-nine-intrinsic-spellings-are-hard-keywords-so-they-cannot-be-user-names]]:**
the deferral there was that these four carry `:width:prec` and the file-first
variadic form, so their parsing had to move with `feature-writeln-as-library`
phase 2. It did not have to. The rewrite is CONDITIONED on a user routine of that
name existing, so an unshadowed `write(x:8:2)` keeps `tkwrite` and reaches the
same statement arm it always did — the format-specifier parsing is untouched
because it is never entered differently. The constraint that was real is the
other one frankD wrote down: **the declaration and the call move together**, and
they do here.

### The corrected enumeration

| name | pxx before | pxx now | fpc 3.2.2 |
| --- | --- | --- | --- |
| `read` `write` `readln` `writeln` | refused at the DECLARATION | **accepted, top level and nested** | accepted |
| `exit` `halt` | **accepted** — never this defect | accepted | accepted |
| `exit := x` / `halt := x` (own-name result) | `a statement cannot start with :=` | unchanged — **this ticket** | accepted |

**The `writeln` control row was the load-bearing one and it was wrong.** This
ticket says of it: *"one of the six is a divergence-free row, so a fix that
simply un-reserves the lot would break parity rather than restore it."* fpc
accepts that declaration. The caution was still correct, for a different reason —
FPC's shadowing is TOTAL, so a blanket un-reserve is not what FPC does either —
but the evidence offered for it did not hold.

**Both errors came from one probe body.** The body called an intrinsic
(`writeln('ok')` / a `System.` qualifier) after shadowing its name, so every row
measured the CALL as well as the DECLARATION and could not tell which had failed.
A probe body that calls nothing separates them, and it is what put `exit` and
`halt` back on the accepted side.

## 2026-09-06 (frankS) — the residual is fixed too, and it was four names

`exit := x > 0` inside `function exit(...)` now compiles, and so do the same
shapes for `halt`, `break` and `continue`. All four have a BARE-STATEMENT arm in
`ParseStatementAST`; every other soft-keyword intrinsic in that chain requires a
following `(`, which `:=` `.` `[` `^` can never be, so the four are the whole
set for the second time in one ticket.

**The predicate that looks right is the wrong one and it is one name away.**
`OwnNameResultSym` (pasparser_lval.inc) is the extracted rule, used by thirteen
lvalue sites, and it carries `if DelphiMode then Exit`. That is correct **for a
READ** — in Delphi a bare own-name read is a reference to the routine, never the
result var. **A WRITE is the `Result` synonym in Delphi too.** Measured: fpc
3.2.2 `-Mdelphi` compiles and runs `function f(x: LongInt): Boolean; begin
f := x > 0; end;`, and so does pxx, through a different arm that had the write
condition spelled out inline. Reaching for the read predicate would have
imported a read-only rule and refused delphi sources that work today.

The write condition is now `OwnNameLValueHere`, with three callers: the tkIdent
arm it was lifted from, the keyword-token twin in the tkRead/tkwrite arm, and
the new guard before the statement dispatch. The first two were already two
spellings of one condition.

### The control could not live in the test it belonged to

The first draft declared all four as functions and used bare `break` /
`continue` statements below as controls. **Both compilers refuse that, at the
same line, for the same reason** — `Wrong number of parameters specified for
call to "continue"`. Once these names are declared, shadowing is TOTAL in pxx
and in fpc alike, so a file that declares them and then claims to test the
statements is testing the user routines under the statements' names. Hence two
files, and the unshadowed one exits 5 on purpose because its bare `halt(5)`
really is the intrinsic. Both halves are asserted: an output-only check would
pass a compiler whose `halt` had stopped halting, an rc-only check one whose
`break` had stopped bounding the loop.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 5f4ffc161.
