# bug: Length() rejects a non-variable argument (literal / expression)

- **Type:** bug (Track A — parser / IR codegen)
- **Status:** done
- **Found:** 2026-06-23, differential probe vs FPC
- **Closed:** 2026-06-23
- **Severity:** medium (every `Length('...')` / `Length(a+b)` must use a temp)
- **Family:** same "intrinsic insists on an l-value variable" shape as
  `bug-setlength-array-element` and `bug-paramstr-inline-argstr`.

## Resolution (2026-06-23)

Front-end only, no codegen change. Two parts:

1. Parser `tkLength`: a string LITERAL folds to its char count
   (`Length('hello')` -> 5). For everything else it now `ParseExpr`s the argument
   (was: required a single ident lvalue), so a concat / function result / any
   string r-value is accepted; the whole-1-D-static-array compile-time fold is
   kept (keyed off the resulting AN_IDENT).
2. IR (`ir.inc`): the Length arg is force-addressed (`isRefArg`) only when it is
   an lvalue (`IsASTLValue`) — a string/array variable/field/element whose `[-8]`
   header the codegen reads from the slot. A non-lvalue managed-string VALUE
   (concat / call result, `tyAnsiString`) is lowered as a value, and the existing
   codegen tyAnsiString-value path reads the length straight from the handle.

Verified byte-identical to FPC: `Length(s+t)`=4, `Length(s+'XYZ')`=5,
`Length(mk)`=6 (function result), `Length('hello')`=5, `Length(s)`=2,
`Length(dynarray)`=3, `Length(staticarray)`=4, `if Length(s+t)=4`. The existing
lvalue paths (var/dynarray/field/open-array, and High/Low which reuse -tkLength)
are unchanged (still lvalue → force-addressed). Minor: `Length(concat)` reads a
transient managed temp that is not released (a small leak, not a miscompile —
FPC frees its temp; the shared managed-arg-temp binding only fires for non-special
calls). Gate: `make test` (self-host byte-identical) + FPC oracle. Closes
bug-length-rejects-non-variable.

## Symptom

`Length` works on a string variable but fails on a string literal or expression:

```pascal
writeln(Length('hello'));      { error: Length: expected string variable }
writeln(Length(s + 'cd'));     { error: unexpected token  (s: string) }
if Length('x') > 0 then ...    { error: Length: expected string variable }
```

Control — a string variable is accepted:

```pascal
var s: string;
s := 'hello';
writeln(Length(s));            { prints 5 }
```

FPC accepts all forms (`writeln(length('hello'))` → 5).

## Expected

`Length` should accept any string r-value — literal, concatenation, function
result — not only a named variable. (Likewise the codegen path that wants the
argument's address should spill an r-value to a temp.)

## Notes

- Found by a vs-FPC differential probe. The same probe re-confirmed
  `bug-writeln-boolean-format` and surfaced `bug-writeln-real-format`.
- Likely one fix covers the "expects a variable" family (Length / SetLength /
  ArgStr) if it is a shared l-value-argument lowering.

## Additional manifestation (2026-06-23) — codegen crash, not just a parse error

When the non-variable argument is a **property getter / function-call result**
(rather than a literal), the failure is not the clean "Length: expected string
variable" message but a codegen abort:

```pascal
var M: TMemo; ... if Length(M.Text) = 0 then ...   { M.Text is a getter }
```
→ `Unsupported linear node in IR codegen! Kind=10 ... IRA=8` (IR_UNSUPPORTED on an
AN_CALL in the lvalue-address path, `ir.inc:744`).

Hit building the Eliah IDE (`Length(memo.Text)` in a smoke check). Control: assign
to a string variable first (`s := M.Text; Length(s)`) compiles. Same root —
`Length` (and the other "expects a variable" intrinsics) must accept an r-value
(literal, function/getter result) by spilling it to a temp. The earlier
`bug-ir-unsupported-call-lvalue` ticket was this same defect and is folded here.
