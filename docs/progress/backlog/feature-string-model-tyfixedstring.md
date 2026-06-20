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

## Landmines

- TTypeKind enum: append only (low ordinals are bootstrap-stable; the seed
  compiler must still parse the new source). See defs.inc comments.
- Don't add a TSymbol field for the cap (MAX_UFIELD overflow breaks self-host);
  use a parallel array.
- Codegen change -> 1-gen reseed, not non-determinism ([[feedback_codegen_reseed_not_nondeterminism]]).
- The compiler itself uses AnsiString (not bare `string`), so the scalar flip
  does not perturb self-host — but Str/Val in the RTL/tests do use frozen
  strings; update or route them through the managed path.
