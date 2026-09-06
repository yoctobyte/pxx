---
slug: bug-p-a-bracket-at-the-head-of-an-argument-cannot-be-an-operators-left-operand
track: P
type: bug
prio: 45
status: done
created: 2026-09-06
found-by: frankS
owner: frankB
blocked-by: []
title: "A `[` at the head of an argument was consumed as the whole argument, so it could never be an operator's left operand"
summary: "CLOSED PENDING-COMMIT. `f([0] + a)` was `expected comma or close parenthesis`; the bracket door consumed a `[...]` at an argument's head as the COMPLETE argument, so a leading element list could never become an operator's LEFT operand. REPORTED WITH THE PAIR THAT MADE IT DIAGNOSABLE (frankS): `f(a + [4])` -- the same expression, operands swapped -- compiled, and `t := [0] + a` -- the same expression, statement position -- compiled, so concatenation and both operands were fine and the ARGUMENT DOOR was the only thing left. Fixed as a REFUSAL to take the door rather than a continuation built into it: TryParseBracketArgForSlot now answers 'not mine' unless the matching `]` is followed by `,` or `)`, and the ordinary expression parser -- which already parses this shape, as the statement row proves -- gets it. A SECOND, LARGER BUG FELL OUT OF ASSERTING THE FIRST AT EVERY CALL PATH: a METHOD's const open-array door parsed its argument as a bare LVALUE, so `o.M(a + b)` -- no bracket anywhere -- stopped at the `+` and was reported as `wrong number of parameters` for a call passing exactly one. ByRefArgStartsExpression had one reason to allow an expression at a by-ref door (`const Variant`) and `const array of T` is the second: both are by-ref internally and neither is a var-binding target. Added ParamBindsAnExpression as the union, rewired at the seven Pascal sites and NOT at pyparser.inc's five (separate frontend). THIRD FIX, in the shared tail: the arity message could not tell a genuine SURPLUS (starts at a comma) from an argument the loop CUT SHORT (stops at an operator) and named a rule the source was not breaking. NINETEEN ROWS, EVERY CALL PATH, CONTENTS NOT LENGTH, green under fpc 3.2.2 with the arrayoperators modeswitch and under pxx; plus a must-not-compile control, because the green file's `var writes` row passes a BARE VARIABLE and is therefore green under the correct gate AND under one widened to every array parameter."
---

# A bracket at the head of an argument is an operator's left operand

```pascal
function N(const r: array of LongInt): LongInt; begin N := Length(r); end;
var a: array of LongInt;
begin
  a := [1,2,3];
  t := [0] + a;        { statement position   -- compiled, length 4 }
  WriteLn(N(a + [4])); { bracket NOT at head  -- compiled, 4 }
  WriteLn(N([0] + a)); { bracket AT the head  -- expected comma or close parenthesis }
end.
```

**The two working rows are the finding.** Measured by frankS at compiler
`caa8808fda7c`: the same expression with the operands swapped compiles, and the
same expression in statement position compiles. Concatenation is fine, both
operands are fine, and the only thing left is the argument door.

## Three fixes, and only the first is the one that was reported

**1. The door (`TryParseBracketArgForSlot`, `pasparser_lval.inc`).** It consumed
a `[...]` at an argument's head as the whole argument. Now it answers "not mine"
unless the matching `]` is followed by `,` or `)` — a REFUSAL to take the door,
not a continuation built into it, because the ordinary expression parser already
parses this shape. The statement row is what proves that; without it the obvious
fix is to teach the door about operators, which is a second expression parser.

**2. A method's const open-array door parsed its argument as a bare LVALUE.**
Found only by asking the first fix at every call path:

```pascal
procedure TCls.P(const r: array of LongInt);
o.P(a + b);   -> wrong number of parameters in call to TCls.P
```

No bracket anywhere. The method argument loops parse a by-ref/array argument as
a bare lvalue unless `ByRefArgStartsExpression` says otherwise, so `a` was the
whole argument and the loop met `+` where it wanted `,` or `)`. The identical
call to a FREE routine compiled, because that path reaches `ParseExpr`.

That predicate had exactly one reason to allow an expression at a by-ref door —
`const Variant`, added because `pair.append(start + i)` failed in pylib.pas's own
body. `const array of T` is the second and the same argument applies verbatim:
by-ref internally, never a var-binding target. Added `ParamBindsAnExpression` as
the union and rewired the **seven** Pascal call sites; `pyparser.inc`'s five keep
`ParamIsConstVariant`, because NilPy is a separate frontend and `PyExprMode`
already covers it there.

**3. The arity message named a rule the source was not breaking.** The shared
tail `ExpectCallRParen` fires whenever the index-driven loop has parsed its
declared number of arguments and `CurTok` is not `)`. Two ways to arrive: a
genuine SURPLUS, which starts at a comma, and a last argument the loop stopped
reading, which stops at an OPERATOR. It reported "wrong number of parameters" for
a call passing exactly one. Split in the tail, not in the seven loops.

## What we do NOT copy from fpc

`o.Bump(a + b)` on `var r: array of LongInt` **compiles under fpc 3.2.2**: it
materialises a temporary, passes it by reference, and the callee's writes are
discarded. We refuse it. Nobody writes `Bump(a + b)` meaning "throw the result
away", so this is a divergence on code someone did not mean to write, and
matching fpc there is not a goal. Refusing leaves the mistake visible.

## The control the green file cannot carry

`test_a_bracket_at_the_head_of_an_argument_is_an_operators_left_operand.pas` has
nineteen rows across free routine, instance method, class method, record method,
interface method, procedural variable and constructor, each printing CONTENTS
rather than `Length` (a length is the same number for a correct concatenation, a
reversed one, and a vector of empty elements), with `a + [4]` as the
always-worked control beside every `[0] + a`.

Its `var writes` row — pass a bare variable to `var r: array of LongInt`, assert
the callee's writes reach the caller — **is not a control for fix 2.** A bare
variable followed by `)` takes the lvalue path whatever the gate says, so that
row is green under the correct gate and under a gate widened to every array
parameter. `test_a_var_open_array_parameter_does_not_bind_an_expression_fail.pas`
is the control: the one spelling whose answer changes if `ProcParamIsConst` is
dropped from `ParamBindsAnExpression`, and it asserts the fix-3 wording by name
so an arity message there fails the row.

## Noted, not fixed

`ParamIsConstVariant` tests `Params[slot].TypeKind = tyVariant` without asking
`IsArray`, so it already answers True for `const a: array of Variant` — the
ELEMENT kind read as the parameter's own. It is harmless (an array parameter is
not a var-binding target either, so True is what the caller wanted) and it is a
fourth landed instance for
[[refactor-p-a-parameters-own-kind-and-its-element-kind-are-one-field-and-the-name-says-neither]].
Left alone deliberately: correcting it changes behaviour in `pyparser.inc` for no
measured reason.

## Log
- 2026-09-06 — reported by frankS with the two working rows already measured,
  which is the reason this took one reading rather than a bisection. Fixed and
  closed the same day; resolved, commit PENDING-COMMIT.
