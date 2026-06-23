# bug: Length() rejects a non-variable argument (literal / expression)

- **Type:** bug (Track A — parser / IR codegen)
- **Status:** backlog
- **Found:** 2026-06-23, differential probe vs FPC
- **Severity:** medium (every `Length('...')` / `Length(a+b)` must use a temp)
- **Family:** same "intrinsic insists on an l-value variable" shape as
  `bug-setlength-array-element` and `bug-paramstr-inline-argstr`.

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
