# C `sizeof("string literal")` returns pointer size, not array size

- **Type:** bug
- **Track:** C (C frontend)
- **Opened:** 2026-06-25
- **Found-by:** lua core survey (lobject.c uses `sizeof("\"]")/sizeof(char)`).

## Symptom

```c
int main(void){ return (int)(sizeof("hello")/sizeof(char)); }
```

gcc: `6` (a string literal has type `char[N]`, N = length + 1 for the NUL).
pascal26: `8` — it treats the literal as a `char*` and takes the pointer size.

## Root cause (suspected)

`sizeof` of a string-literal node resolves the operand's type to a pointer
(tyPointer, 8 bytes) rather than a fixed `char` array of `len+1`. The C frontend
already knows the literal's length at lex time (`tkString` SVal), so `sizeof` on
an `AN_STR_LIT` should yield `Length(s) + 1`.

## Fix sketch

In the C `sizeof` handler, special-case a string-literal operand: size =
(byte length of the literal) + 1. Watch escapes — the value is the DECODED
byte length (already what the lexer stored in SVal), not the source spelling.

## Notes

Value bug, not a parse error (the program compiles, the constant is just wrong),
so it does not by itself block parsing — but lua/sqlite use
`sizeof(string)/sizeof(char)` in buffer-size const expressions, so a wrong value
can cascade. Lower priority than the parse-blocking `unexpected token` tail.
