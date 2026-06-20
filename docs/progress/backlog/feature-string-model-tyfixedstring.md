# String model overhaul: tyFixedString + managed `string` + Str/Val

- **Type:** feature (type system + all backends + RTL)
- **Status:** backlog
- **Owner:** Track A
- **Opened:** 2026-06-20
- **Relates:** [[bug-string-type-size-mismatch]], [[bug-rtti-offset-static-array]]

## Goal (the intended, unambiguous string model)

| source           | internal kind        | semantics                                   |
|------------------|----------------------|---------------------------------------------|
| `string` (managed mode, the default) | tyAnsiString | managed, ref-counted, 8-byte handle |
| `string` (`-uPXX_MANAGED_STRING`)     | tyFixedString | frozen, inline, 255 default          |
| `string[N]`      | tyFixedString (cap N) | frozen, inline, N bytes                     |
| `shortstring`    | tyFixedString (cap 255) | frozen, inline, 255                       |
| `ansistring`     | tyAnsiString          | managed (already correct)                   |

`tyFixedString` (new) disambiguates the frozen fixed/short string from the
managed AnsiString. Today `tyString` is overloaded (frozen-default AND sized),
which is the root of the size/offset confusion.

## What's already done (per-use quick fix, commit f7c9dc5)

`array of string` elements promote to tyAnsiString in managed mode (ParseTypeKind
`tkString_T`, gated on the preceding `of`). Scalar `string` stays frozen tyString
so Str/Val keep working. Track B's PCL list controls are unblocked. This ticket
is the FULL arc that supersedes that stopgap.

## Why it's a real arc (blast radius)

`tyString` is special-cased ~250 times across parser.inc (53), symtab.inc (38),
ir.inc (24), and the six backends (ir_codegen* — x64 27, i386 25, arm32 24,
aarch64 20, riscv32 7, xtensa 9). `tyFixedString` must be handled everywhere
`tyString` (frozen) is, OR be normalised to a shared frozen-string path.

## Recommended approach (low-risk, incremental)

1. **Add `tyFixedString` to the TTypeKind enum** (defs.inc), at the END so the
   bootstrap-stable low ordinals don't shift (the enum has a documented
   stability contract — adding at the tail is safe; inserting is NOT).
2. **A single predicate** `TypeIsFrozenString(tk) := (tk = tyString) or
   (tk = tyFixedString)` and route all codegen through it, rather than adding
   tyFixedString arms at 250 sites. Most backends already branch on
   `= tyString`; widen those to the predicate. Keep tyString as the legacy
   frozen alias during migration so nothing breaks mid-flight.
3. **Per-symbol capacity**: store the fixed cap (255 / N) per symbol
   (e.g. SymStrCap parallel array — NOT a TSymbol field, per the MAX_UFIELD
   landmine [[project_tsymbol_field_landmine]]). AllocVar/AllocArray/field-alloc
   size the slot from it. Fixes the 8 MB relic (STRING_CAP stays the compiler's
   token buffer only) and gives string[N] its real width.
4. **Resolver**: `shortstring` -> tyFixedString(255); `string[N]` ->
   tyFixedString(N); bare `string` -> tyAnsiString in managed mode, tyFixedString
   in frozen mode. Remove the per-use `of`-peek stopgap once scalars flip safely.
5. **Str/Val managed support** (the make-test blocker): `Str(x, s)` / `Val(s, x)`
   must accept a tyAnsiString destination/source. Today StrInt/StrFloat write a
   frozen buffer; add the managed path (write into / read from the handle).
   THIS is what made the global flip segfault test_float_str_val.
6. **Fix the frozen SIZED-string writeln/Length bug** (pre-existing): writeln /
   Length of a `string[N]` returns a code address. Plain frozen `string` works;
   the sized path is broken. Likely falls out of the clean tyFixedString codegen,
   but verify with a dedicated test.
7. **Validate per target**: byte-identical self-host (frozen build `-u` exercises
   tyFixedString heavily; managed build exercises the AnsiString path). Reseed
   (`make bootstrap`) on the inevitable codegen change. Cross targets + ESP must
   still build (riscv/xtensa have the leanest string support; keep tyFixedString
   within what they already do for tyString).

## Order

enum + predicate (no behaviour change, byte-identical) -> per-symbol cap + sizing
-> resolver wiring (shortstring/string[N]) -> scalar `string` flip + Str/Val
managed -> sized-writeln fix -> drop the `of`-peek stopgap. Commit each slice;
each should keep make test green.

## Progress 2026-06-20 (slices 1-4 part1 DONE; scalar flip HELD)

Three frozen beasts confirmed with the user (NOT two): `tyShortString` (byte len
prefix, cap<=255, FPC ABI), `tyFixedString` (NativeInt length-WORD prefix, any
cap N), `tyAnsiString` (managed, exists). KEY finding: today's frozen `tyString`
is already WORD-prefix (`mov [rdi],rcx` 8 bytes at offset 0, then chars at +8) —
so `tyFixedString` is a *relabel* of the existing frozen codegen (reuses it
unchanged); `tyShortString` is the genuinely-new byte-prefix layout.

- **Slice 1** (6cc85fc): `tyShortString`(25)+`tyFixedString`(26) appended to
  TTypeKind tail; `TypeIsFrozenString(tk)` predicate. Byte-identical.
- **Slice 2** (fc27f3a): `SymStrCap[]` parallel array + `DEFAULT_STR_CAP=255` +
  `FrozenStrSlotSize(tk,cap)` (Fixed=cap+8, Short=cap+1). Alloc* size+reset it.
  Legacy tyString keeps its 8MB-global relic (dies with the alias).
- **Slice 3** (1c8fa71): resolver `string[N]`->tyFixedString(N) (consumes its own
  `[N]`), `shortstring`->tyFixedString(255) INTERIM (word layout; true
  byte-prefix tyShortString deferred). `StrValTk(tk)` splits STORAGE kind
  (tyFixedString, for sizing + symbol-direct checks) from VALUE kind (presents as
  tyString, so ~150 value-checks work unwidened). Widened the symbol-direct /
  addressing frozen checks to the predicate (IRVerify bound, AN_IDENT LEA, string
  char-index lo=-7, array-of-string[N] element stride from SymStrCap). x64 path.
  Slice 5 (sized-string writeln/Length bug) FELL OUT here — string[N] now correct.
- **Slice 4 part 1** (2f55bfb): Val/ValFloat source param `string`->`AnsiString`
  (frozen args coerce, managed pass through; one proc). Str already worked
  (frozen->managed assign). test_str_val_managed added.

All four: make test green, self-host fixedpoint byte-identical.

### REMAINING
- **Slice 4 part 2 (HELD, needs coordination):** flip scalar bare `string` ->
  tyAnsiString in managed mode + drop the `of`-peek stopgap (parser.inc
  ParseTypeKind tkString_T). Makes managed the DEFAULT string model -> Track B
  must re-pin the stable binary. User wants managed-default as the end state but
  the flip is gated on re-pin coordination.
- **Slice 3b (cross backends):** widen the symbol-direct frozen `= tyString`
  checks in ir_codegen386/arm32/aarch64/riscv32/xtensa for tyFixedString. Value
  checks already work via StrValTk normalisation. Only affects cross FEATURE
  builds (x64 + cross self-host unaffected — compiler.pas uses AnsiString).
- **tyShortString true codegen:** byte-length-prefix layout for FPC-ABI shortstring
  (varargs/TVarRec). `shortstring` keyword currently aliases tyFixedString(255).
- **Slice 6:** byte-identical BOTH builds, cross+ESP build, extend tests.

## Landmines

- TTypeKind enum: append only (low ordinals are bootstrap-stable; the seed
  compiler must still parse the new source). See defs.inc comments.
- Don't add a TSymbol field for the cap (MAX_UFIELD overflow breaks self-host);
  use a parallel array.
- Codegen change -> 1-gen reseed, not non-determinism ([[feedback_codegen_reseed_not_nondeterminism]]).
- The compiler itself uses AnsiString (not bare `string`), so the scalar flip
  does not perturb self-host — but Str/Val in the RTL/tests do use frozen
  strings; update or route them through the managed path.

## Next-session prompt (start the tyFixedString arc here)

> Track A (compiler). Execute the string-model overhaul: introduce `tyFixedString`
> and make `string` follow the mode. Read THIS ticket
> (docs/progress/backlog/feature-string-model-tyfixedstring.md) and
> [[bug-string-type-size-mismatch]] first.
>
> Target model: `string` = managed AnsiString in managed mode (the DEFAULT;
> `-uPXX_MANAGED_STRING` = frozen); `string` in frozen mode + `string[N]` +
> `shortstring` = the NEW `tyFixedString` (frozen, inline, right-sized, 255
> default); `ansistring` = tyAnsiString (already correct). `tyFixedString` exists
> to end the tyString overload (frozen-default vs sized) that caused the
> size/offset bugs.
>
> Already done (don't redo): the per-use stopgap — `array of string` ELEMENTS
> promote to AnsiString in managed mode (ParseTypeKind tkString_T, gated on the
> preceding `of` token), scalar `string` stays frozen so Str/Val work. Commit
> f7c9dc5, pinned v23. This arc supersedes it; drop the `of`-peek once scalars
> flip safely.
>
> Blast radius: tyString is special-cased ~250x across parser.inc(53),
> symtab.inc(38), ir.inc(24), ir_codegen*.inc (x64 27 / i386 25 / arm32 24 /
> aarch64 20 / riscv32 7 / xtensa 9). Do NOT add 250 tyFixedString arms — add a
> predicate `TypeIsFrozenString(tk) := (tk=tyString) or (tk=tyFixedString)` and
> widen the existing `= tyString` (frozen) checks to it. Keep tyString as the
> legacy frozen alias during migration.
>
> Slices, each must keep `make test` green and reseed cleanly via `make bootstrap`
> (codegen change = 1-gen reseed, NOT non-determinism):
> 1. Append `tyFixedString` to the TTypeKind enum (defs.inc) at the END (low
>    ordinals are bootstrap-stable; inserting breaks the seed). Add the predicate.
>    No resolver/codegen change yet -> byte-identical.
> 2. Per-symbol capacity for fixed strings: a parallel array (NOT a TSymbol field
>    — MAX_UFIELD overflow landmine), default 255. AllocVar/AllocArray/field-alloc
>    size the slot from it. STRING_CAP stays ONLY the compiler token buffer (kills
>    the 8MB global-string relic at symtab.inc:1419 etc).
> 3. Resolver (parser.inc ParseTypeKind): `shortstring` -> tyFixedString(255);
>    `string[N]` -> tyFixedString(N); bare `string` -> tyAnsiString (managed) /
>    tyFixedString (frozen). Route tyFixedString through the frozen-string codegen
>    via the predicate in every backend.
> 4. Str/Val managed support: `Str(x,s)` / `Val(s,x)` must accept a tyAnsiString
>    dest/source (this is what segfaulted test_float_str_val under the global
>    flip). Then flip scalar `string` -> AnsiString in managed mode and drop the
>    `of`-peek stopgap.
> 5. Fix the pre-existing frozen SIZED-string writeln/Length bug (`string[N]` /
>    current `shortstring` print a code address; plain frozen `string` works) —
>    likely falls out of clean tyFixedString codegen; add a test either way.
> 6. Validate per target: byte-identical self-host BOTH builds (frozen `-u`
>    exercises tyFixedString; managed exercises AnsiString). Cross + ESP must
>    still build (riscv/xtensa have the leanest string support — keep tyFixedString
>    within what they already do for tyString). New tests:
>    test/test_shortstring.pas, test/test_string_sized.pas, extend
>    test_array_of_string.pas. Commit each slice; stay in compiler/**, `git commit
>    -- <paths>`, shared checkout with Track B (owns lib/**). No push without OK.
