# Indexing a string constant miscompiles (`const RAMP='...'; RAMP[i]`)

- **Type:** bug (codegen + parser)
- **Track:** A — `compiler/**`
- **Status:** backlog (filed by Track B; HIGH severity — silent wrong codegen)
- **Owner:** — (Track A)
- **Opened:** 2026-06-25
- **Found-by:** [[feature-demo-mandelbrot]] — the ASCII renderer maps an escape
  count to a shade with `line := line + RAMP[ri + 1]` where
  `const RAMP = ' .:-=+*#%@'`. The integer CHECKSUM gate passes (escape counts
  `n` are correct), but the **visual grid is garbage on pxx** while FPC renders a
  correct Mandelbrot — the demo's checksum oracle masks the bug.

## Symptom

Indexing a **string constant** with `[]` returns the wrong thing. A string
**variable** indexed the same way is correct.

```pascal
const RAMP = ' .:-=+*#%@';
var c: Char; i: Integer; sv: AnsiString;
begin
  i := 3; sv := RAMP;
  c := sv[i];   { 'C' var[var] -> ':'  CORRECT }
  c := sv[3];   { 'D' var[lit] -> ':'  CORRECT }
  c := RAMP[3]; { 'A' const[lit] -> garbage byte  WRONG (want ':') }
  c := RAMP[i]; { 'B' const[var] -> garbage byte  WRONG (want ':') }
end.
```

In **string context** the broken element evaluates to the *whole* constant
string instead of one character:

```pascal
s := 'X' + RAMP[i];   { -> 'X .:-=+*#%@'  (want 'X:') }
s := RAMP[i];         { -> ' .:-=+*#%@'   (want ':')  }
```

So `line := line + RAMP[ri+1]` appends the entire 10-char ramp every iteration —
the source of the repeated-`' .:-=+*#%@'` Mandelbrot rows.

### Parser facet (likely related)

A string-constant index used **directly as a call argument** fails to parse:

```pascal
writeln('x=[', RAMP[3], ']');   { pascal26: error: unexpected token () }
```

Assigning to a temp first (`c := RAMP[3]; writeln(..., c, ...)`) sidesteps the
parse error but then hits the codegen bug above.

## Discriminator: only string constants, not const arrays

A typed const **array** indexes correctly with both a literal and a variable
index — so the const-storage + index machinery is fine in general:

```pascal
const TBL: array[0..4] of Integer = (10,20,30,40,50);
  i:=2; TBL[i]=30  TBL[2]=30   { both CORRECT }
const HEX = '0123456789abcdef';
  HEX[i+1]  { garbage — WRONG }
```

So the bug is specific to **string-literal constant element access**, not const
indexing as a whole. Points Track A at the char-from-const-string lowering, not
the const/index path.

## Root cause (hypothesis)

A `const s = 'literal'` is folded as a string literal; element access `s[idx]`
is not lowered to a character load from the literal's storage. It instead yields
the whole constant (string context) or an uninitialised/garbage char (char
context). The index expression is evaluated but discarded. String *variables*
take the correct managed-string index path, which is why only the const form is
wrong.

## Impact

Any const lookup table indexed at runtime — ramps, hex digit tables
(`const HEX='0123456789abcdef'; HEX[(b shr 4)+1]`), shade/palette maps — is
silently wrong on pxx. Common idiom; produces no error, just bad data.

## Done when

- `const R=' .:-=+*#%@'; c:=R[3]` gives `c=':'` (Ord 58); var and literal index.
- `'X' + R[i] = 'X:'` and `R[i] = ':'` in string context.
- `writeln('[', R[3], ']')` parses and prints `[:]`.
- `examples/mandelbrot` renders the correct bulb on pxx (matches FPC visual),
  not just the matching checksum.
- Regression test under `make test`; self-host fixedpoint byte-identical.

## Resolution (2026-06-25, v61)

Two compounding gaps, both fixed:

1. **Parser** (`ParseFactor`, untyped-string-const branch): a string const
   resolved to an `AN_STR_LIT` but a trailing `[i]` was never consumed, so the
   index was dropped (string context returned the whole string; call-arg context
   `writeln(…, RAMP[3], …)` failed to parse). Now a trailing `[expr]` wraps the
   `AN_STR_LIT` in an `AN_INDEX` tagged tyChar.
2. **Codegen** (`IRLowerAddress`, `AN_INDEX`): with an `AN_STR_LIT` base, the
   address used `IRLowerAddress(baseNode)` — wrong, the literal has no addressable
   slot. The literal's VALUE (`IR_CONST_STR`) is a pointer to the frozen
   `[len][data]` blob (data at +8), identical layout to a frozen-string variable
   slot, so index it with `base = IRLowerAST(baseNode)`, `lo = -7`, stride 1,
   tyChar.

Verified char + string context, literal + variable index, call-arg context, and
that const ARRAY indexing is unaffected — on x86-64 / i386 / aarch64 / arm32.
Regression `test/test_const_string_index.pas` under `make test`. Self-host
byte-identical; pinned v61.

(The related typed-string-const initializer parse gap remains separate —
[[bug-string-const-index-and-typed-init]].)
