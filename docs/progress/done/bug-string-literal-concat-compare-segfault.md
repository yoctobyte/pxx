# bug: comparing against a concatenation of string literals (`x = 'a' + 'b'`) segfaults

- **Type:** bug (codegen — constant string concat as a comparison operand)
- **Status:** done
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

## Log
- 2026-06-25 — fixed (9f8d568). Root cause as suspected: a runtime
  string-concat result fed into the hand-emitted string-compare path crashes.
  Fix = constant folding instead: the ESP-only literal-concat fold in ir.inc
  (`'a'+'b'` → one interned IR_CONST_STR) made target-independent, so a
  literal-concat operand becomes a single literal — identical to the known-good
  single-line form. Subtlety: the folded literal must be tagged tyString (a
  plain literal's kind), NOT the surrounding expression's ASTTk — a
  Concat-synthesised `+` chain is tyAnsiString in managed mode, and tagging the
  static literal tyAnsiString made managed paths release it as a heap handle →
  crash at scope exit (regressed test_concat_intrinsic; caught + fixed before
  commit). Regression test test/test_str_literal_concat_compare.pas. Verified
  x86-64 + aarch64/arm32/i386; make test + self-host + cross-bootstrap
  byte-identical (1-gen reseed). Track B can drop the single-line-literal
  workaround in lib_sha256 / lib_aesgcm.
