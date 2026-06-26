# String model overhaul: tyFixedString + managed `string` + Str/Val

- **Type:** feature (type system + all backends + RTL)
- **Status:** done-followup
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

## Next-session prompt (slice 4p2 — the HELD scalar-string managed flip)

> **Track A (compiler) — string-model slice 4p2: flip scalar `string` ->
> managed default.**
>
> Pinned stable is **v25**. The string-model arc is done through slice 4p1:
> `tyShortString`/`tyFixedString` exist, `StrValTk` splits storage-vs-value kind,
> `SymStrCap[]` sizing, `string[N]`->`tyFixedString`, `Val`/`ValFloat` params
> widened to `AnsiString`. Read THIS ticket (the Progress + Remaining sections
> above), [[bug-managed-to-frozen-string-assign-crash]], and
> [[design-overloadable-intrinsics]] first. **This slice was deliberately HELD
> because it changes the pinned binary's behavior — Track B must re-pin after.**
>
> **The change (one site).** `compiler/parser.inc`, `ParseTypeKind`, `tkString_T`
> arm (~line 6663). Today:
> ```pascal
> else if PasDefineExists('PXX_MANAGED_STRING') and
>         (TokPos >= 2) and (Tokens[TokPos - 2].Kind = tkOf) then
>   Result := tyAnsiString          { only array-of-string ELEMENTS flip }
> else
>   Result := tyString;
> ```
> Drop the `of`-peek restriction so **scalar bare `string` also resolves to
> `tyAnsiString`** when `PXX_MANAGED_STRING` is defined (the default — set in
> `lexer.inc:461`). `string[N]`/`shortstring` stay `tyFixedString`;
> `-uPXX_MANAGED_STRING` stays all-frozen.
>
> **Why it's not a one-liner.** The naive drop previously segfaulted
> `test_float_str_val` — scalar frozen-buffer builtins (`Str`, `Val`, char-index,
> concat) assumed a frozen layout. 4p1 widened `Val`/`ValFloat`; this slice must
> verify **every** scalar `string` use survives as managed: `Str(x,s)`, `s[i]`,
> `s := a+b`, `for c in s`, length/compare, var/const/by-ref params, function
> returns. Where a frozen buffer is genuinely required, route through
> `tyFixedString` explicitly.
>
> **The payoff (acceptance):** the crash in
> [[bug-managed-to-frozen-string-assign-crash]] must vanish — this repro prints,
> not segfaults:
> ```pascal
> program r; var a: array of string; s: string;
> begin SetLength(a,1); a[0]:='hello world long enough'; s:=a[0]; writeln(s); end.
> ```
> (currently exit 139 under `-dPXX_MANAGED_STRING`). Add it as a regression test
> both directions (managed<->frozen).
>
> **Hard gates:** `make test` green; self-host **byte-identical** (codegen change
> = 1-gen reseed -> `make bootstrap`, NOT non-determinism); cross
> (i386/aarch64/arm32) + ESP still build. Compiler source uses `AnsiString` not
> bare `string`, so self-host shape is unperturbed — but RTL/builtin/tests use
> bare `string`, audit those.
>
> **Coordination (the whole reason this was held):** after green + byte-identical,
> `make stabilize` -> `make pin` -> commit `stable_linux_amd64/`. **This moves
> Track B's ground** — bare `string` now means managed in everything they build.
> Announce the re-pin; Track B re-runs `make lib-test` / `make demos` against the
> new pinned and drops the explicit-`AnsiString` workaround in
> `lib/pcl/stdctrls.pas` (commit 6355d7d). Once both tracks rebuild clean, the
> held flip is done and A/B continue normally.
>
> Stay in `compiler/**`; `git commit -- <paths>`; push freely once stable
> (lane gate green) per the updated workflow norm.
