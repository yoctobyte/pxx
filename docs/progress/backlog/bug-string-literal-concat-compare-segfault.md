# bug: comparing against a concatenation of string literals (`x = 'a' + 'b'`) segfaults

- **Type:** bug (codegen — constant string concat as a comparison operand)
- **Status:** backlog
- **Track:** A
- **Opened:** 2026-06-25
- **Found-by:** Track B, test vectors in `test/lib_sha256` and `test/lib_aesgcm` —
  long expected hex values split across two string literals with `+` crashed
  until joined onto one line.

## Symptom

A `=` comparison whose operand is a compile-time concatenation of two string
literals segfaults at runtime:

```pascal
var a: AnsiString;
begin
  a := 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  if a = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' +
         'cccccccccccccccccccccccccccccccc' then writeln('eq') else writeln('neq');
end.            { SIGSEGV }
```

Narrowing:
- A plain **assignment** of a literal concat works: `a := 'x' + 'y';` is fine.
- The crash is the literal-concat appearing as a **comparison operand**
  (`… = 'x' + 'y'`), with a function-result or a variable on the other side.

## Workaround

Put the literal on a single line (no `+`), or assign the concatenation to a
variable on its own statement and compare the variable. Used in `lib_sha256` /
`lib_aesgcm` (single-line hex literals). See [[track-b-workarounds]].

## Likely cause

The constant-folded concatenated string temporary is mishandled when it is an
argument to the comparison lowering (a bad/freed temp pointer fed to the string
compare), whereas the assignment path materialises it correctly.

## Acceptance

- `if x = 'a' + 'b' then …` evaluates correctly (no crash) for AnsiString.
- Regression test.
