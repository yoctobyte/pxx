---
summary: "`Inc(FuncName)` is `undefined variable` — Inc/Dec resolve their target with a bare FindSym, which cannot see a proc name, so FPC's `FuncName`-as-`Result` synonym works everywhere except here"
type: bug
track: P
prio: 45
status: done
---

# Inc/Dec does not accept the enclosing function's own name

- **Type:** bug (Pascal frontend / lvalue resolution) — Track P
- **Opened:** 2026-08-27
- **Found by:** the FPC-compiler corpus march, `cutils.pas:1429`:
  `inc(minilzw_encode[0])`. Recorded as flagged item (2) on
  `bug-p-index-0-of-a-frozen-string-is-not-the-length-byte`.

In objfpc/default mode a function's own bare name is a synonym for `Result`.
pxx honoured that on the **read** side (`F := F + x`) and on the **assign** side
(`F[1] := 'X'`) — and not in `Inc`/`Dec`:

```pascal
function Build: shortstring;
begin
  Build := '';
  Inc(Build[0]);        { error: undefined variable (Build) }
  Build[Length(Build)] := 'x';
end;
```

## Root cause

The `Inc`/`Dec` arm (`pasparser_stmt.inc`) resolves its target with
`argIdx := FindSym(CurTok.SVal)` before handing off to `ParseLValueAST`.
`FindSym` looks up **symbols**; a function name is a **proc**, so it missed and
`ParseLValueAST(-1, …)` reported the name as undefined. The expression-read arm
(`pasparser_expr.inc:7322`) had the rule spelled out inline; nothing else did.

## Fix

The rule is now a routine — `OwnNameResultSym(name)` in `pasparser_lval.inc`,
where both the expression and statement parsers can see it — answering the
result symbol when `name` is the current function's own name and `-1` otherwise
(including in `{$mode delphi}`, where a bare own name is a reference to the
routine and `Result` is the only spelling). The `Inc`/`Dec` arm consults it only
when `FindSym` found nothing and the next token is not `(`, so a local that
shadows the function still wins and `Inc(F(x))` is still not an lvalue.

## Outcome — FIXED, 2026-08-27

`test/test_inc_dec_on_own_name.pas` (wired into `test-core`) is
**byte-identical to the FPC 3.2.2 oracle** across six rows: `Inc`/`Dec` with and
without a step on an Integer result, the shortstring length-byte build loop that
started this (`Inc(Built[0])` three times then `Dec`), a `.field` selector on a
record result, a local whose name shadows nothing being incremented alongside
the result, and a local `acc` in a loop as a guard that ordinary `Inc` is
untouched.

`gate.sh quick` GREEN; Pascal conformance 346/0/170/34, C conformance 220/0,
fgl 7/7.

**Corpus march: `cutils.pas` clears line 1429.** What remains in that unit is
two missing System-unit functions — `BsfQWord` (line 960) and `octstr`
(line 1092) — and nothing else. Those are RTL surface, not frontend defects.

## Log
- 2026-08-27 — resolved, commit c6a73e2d5.
