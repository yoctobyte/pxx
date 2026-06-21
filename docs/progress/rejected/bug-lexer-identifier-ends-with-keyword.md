# Bug — Lexer misidentifies identifiers ending with keyword names (e.g. 'Class')

- **Type:** bug
- **Status:** rejected (not reproducible — misdiagnosis)
- **Owner:** —
- **Opened:** 2026-06-21

## Description

The compiler scanner/lexer appears to check for keywords (like `class`) using a suffix or substring match rather than full-word boundaries. As a result, user-defined identifiers that contain or end with a keyword name (such as `TMyClass` ending with `Class`) are incorrectly tokenized as keyword tokens rather than standard identifier tokens. This leads to unexpected parse errors like `Expected: :=, but got: .` or `unexpected token` on valid variable declarations and method calls.

## Steps to Reproduce

This code fails to compile:
```pascal
program test_bug;
type
  TMyClass = class
    Value : Integer;
    procedure Reset;
  end;

procedure TMyClass.Reset;
begin
  Self.Value := 0;
end;

var c: TMyClass;
begin
  c := TMyClass.Create;
  c.Reset; // pascal26:16: error: unexpected token (Expected: :=, but got: .)
end.
```

If `TMyClass` is renamed to anything not containing/ending with `Class` (e.g. `TMyClazz` or `TLifeHandler`), it compiles and runs successfully.

## Expected Behavior

The lexer should strictly tokenize keywords when they match exactly on identifier boundaries (e.g. using `[a-zA-Z_][a-zA-Z0-9_]*` match rules) rather than identifying them as substrings or suffixes within larger user-defined identifiers.

## Resolution — REJECTED (not reproducible)

- 2026-06-21 - The exact repro above compiles AND runs on the current compiler
  (`c := TMyClass.Create; c.Reset;` → ok, exit 0). Also verified `TWidgetClass`,
  `TThingClass`, and identifiers like `arraything` / `recordval` — all tokenize
  as plain identifiers and run correctly.
- The lexer does NOT suffix/substring-match keywords. The keyword classifier
  (`lexer.inc`) scans a full identifier, then dispatches on `Length(s) = N` and
  compares the whole word char-by-char. An 8-char `TMyClass` is only ever tested
  against 8-char keywords, so it can never collide with the 5-char `class`. Word
  boundaries are exact by construction.
- The reported `Expected: :=, but got: .` was almost certainly a downstream
  symptom of an UNRELATED defect in the reporter's fuller program (e.g. the
  64-bit dyn-array-field pointer truncation, `bug-movslq-on-64bit-pointer-load`,
  which segfaults/miscompiles class+record+dynarray code — fixed in 37e22ad),
  misattributed to the lexer. No lexer change is warranted.
