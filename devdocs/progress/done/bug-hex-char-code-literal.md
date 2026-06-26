# `#$NN` / `#%NN` / `#&NN` char-code literals broken (hex/bin/oct escape)

- **Type:** bug (lexer) — correctness, silent miscompile
- **Status:** done (2026-06-24) — fixed in lexer.inc `#` branch: radix dispatch
  ($/%/& before the digit loop) + empty-prefix lex error. Lexer-only, self-host
  byte-identical (no reseed). Regression test `test/test_hex_char_code.pas`
  (all three radices, statement + char const + subrange set const) under
  `make test`. Pinned for B to re-probe synacode.
- **Owner:** — (**Track A** — `compiler/**`)
- **Opened:** 2026-06-24
- **Found-by:** Synapse recon ([[feature-synapse-compile-check]]) — `synacode.pas`
  line 94 (`URLSpecialChar: TSpecials = [#$00..#$20, ..., #$7F..#$FF]`).

## Symptom

The `#NN` char-code literal only accepts a **decimal** code. The FPC forms with a
radix prefix — `#$` (hex), `#%` (binary), `#&` (octal) — are mis-lexed:

- In a **constant expression** (typed const, string const, subrange, set
  literal) it hard-errors, e.g. `const C: char = #$FF;` →
  `Expected: begin, but got:  (Kind: 2)`.
- In a **statement/runtime expression** it does NOT error but silently produces
  the **wrong value** (`Chr(0)`):

```pascal
var c: char;
begin c := #$41; writeln(Ord(c)); end.   { prints 0, must be 65 }
```

Decimal `#65` works everywhere; only the radix-prefixed forms break.

### Minimal repros (all on pinned v49)

```pascal
program p; const C: char = #$FF; begin end.              { ERROR }
program p; type T=set of char; const C:T=[#$FF]; begin end.   { ERROR }
program p; var c:char; begin c:=#$41; writeln(Ord(c)); end.   { compiles, prints 0 }
```

## Root cause

`compiler/lexer.inc:1592-1598` — the unified string/char-code literal lexer reads
the code after `#` with a **decimal-only** digit loop:

```pascal
else if Source[SrcPos] = '#' then
begin
  Inc(SrcPos); n := 0;
  while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do
    begin n := n*10 + (Ord(Source[SrcPos])-48); Inc(SrcPos); end;
  AppendChar(s, Chr(n));
end
```

For `#$FF`: consumes `#`, the loop sees `$` (not `0'..'9`), consumes zero digits,
appends `Chr(0)`, then the outer loop breaks on `$` (not `'` or `#`). The token
ends as a 1-char string `#0` and `$FF` dangles as the next token — hence the
hard error in const-expr context and the silent `Chr(0)` in statement context.

## Fix

After `Inc(SrcPos)` past `#`, dispatch on the radix prefix before reading digits
(same set the integer lexer already handles — `$`/`%`/`&`):

- `$` → hex digits `['0'..'9','a'..'f','A'..'F']`
- `%` → binary `['0'..'1']`
- `&` → octal `['0'..'7']`
- else → decimal `['0'..'9']` (current behaviour)

Reuse the existing radix scan from the integer-literal path (lexer.inc has `$`
hex and `%` binary integer scanners already; factor or mirror them). Guard the
empty-digit case (a lone `#$` with no digits) with a lex error instead of
silently appending `Chr(0)`.

## Done when

- `c := #$41` yields `Ord(c) = 65`; `#%01000001` and `#&101` likewise = 65.
- `const C: char = #$FF;`, `[#$00..#$20, #$7F..#$FF]` set const, and the exact
  `synacode.pas:94` `URLSpecialChar` declaration all parse.
- A lexer/parse regression test covering all three radices in both const and
  statement context lands under `make test`.
- Self-host fixedpoint still byte-identical; `make stabilize` + `make pin` so
  Track B can re-probe `synacode` ([[feature-synapse-compile-check]]).
