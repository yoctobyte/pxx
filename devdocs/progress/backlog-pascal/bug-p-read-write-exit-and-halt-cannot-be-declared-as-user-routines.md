---
slug: bug-p-read-write-exit-and-halt-cannot-be-declared-as-user-routines
title: "READ/WRITE/READLN/WRITELN ARE DONE — what is left is `exit := x` inside a function named `exit`"
track: P
prio: 40
type: bug
status: backlog
owner: "frankS"
blocked-by: []
summary: "THE FOUR-NAME HALF IS FIXED (2026-09-06, frankS): read/write/readln/writeln are declarable as user routines at top level and nested, and the calls reach them, through a shadow predicate and a token rewrite rather than a lexer conversion -- see [[bug-p-nine-intrinsic-spellings-are-hard-keywords-so-they-cannot-be-user-names]]. TWO ROWS OF THIS TICKET'S ENUMERATION WERE WRONG AND THE WRONG ONE IS THE CONTROL. (1) `writeln` is NOT a parity row: fpc 3.2.2 ACCEPTS `function writeln(x: LongInt): Boolean` -- what it refuses is this ticket's probe BODY, where the console `writeln('ok')` after the shadowing declaration is an ARGUMENT-TYPE error at the CALL (fpc: `Incompatible type for arg no. 1`), because FPC shadowing is TOTAL. A row where both sides refuse for DIFFERENT reasons at DIFFERENT positions is not parity, and it reads as parity because 'refused' is the same string on both sides. (2) `exit` and `halt` were never in this set: both DECLARE fine and always did -- proven by the nested probe, which accepts them -- and paslexer.inc has zero matches for either spelling, because they were converted to soft keywords already (its own comment at :155 says so). SO THE SET WAS THE FOUR NAMES paslexer.inc GIVES A TOKEN KIND TO, not five. WHAT IS LEFT, and all this ticket now claims: `exit := x > 0` inside `function exit(...)` is `a statement cannot start with :=`. That is OWN-NAME RESULT ASSIGNMENT on a soft-keyword intrinsic, a third defect at a third position -- ParseStatementAST's Halt/Exit arm has a shadow test but no own-name-lvalue test, so the intrinsic wins over the result var. `Result := x` in the same function compiles and runs today. OwnNameResultSym (pasparser_lval.inc:295) is the rule already extracted; the arm does not ask it."
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
