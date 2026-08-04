# Four integer parsers, four different answers — no radix prefixes, silent overflow

- **Type:** bug — Track B (library), tag `compat` (FPC parity)
- **Status:** done
- **Resolved:** 2026-08-04 in `622a8a055` (verified on origin/master after the rebase)
- **Opened:** 2026-08-04
- **Found by:** `tools/fpc_diff_probe.sh`, new `su-strtoint-hex` and
  `su-inttostr64` cases.

## The root cause is the structure, not the individual behaviours

`StrToIntDef`, `StrToInt64Def`, `TryStrToInt` and `TryStrToInt64` were **four
independent implementations**. FPC funnels all four through one `Val`, and its
four answers agree for every input. pxx's did not agree with each other:

| input | StrToIntDef | TryStrToInt | StrToInt64Def | TryStrToInt64 | FPC (all four) |
| --- | --- | --- | --- | --- | --- |
| `'42 '` | reject | **42** | reject | reject | reject |
| `'$FF'` | reject | reject | reject | reject | 255 |
| `'99999999999999999999999'` | -159383553 | -159383553 | 200376420520689663 | 200376420520689663 | reject |

Any test written against one entry point would have passed while the others
were wrong, which is exactly what happened.

## The three defects

1. **No radix prefixes.** FPC accepts `$FF` / `0x10` / `0X10` (hex), `&17`
   (octal), `%1010` (binary), with the sign *before* the prefix (`-$FF`). pxx
   accepted none of them. `$` in particular is the everyday Pascal spelling of
   a hex literal.

2. **64-bit overflow wrapped silently.** `'-9223372036854775809'` — one past the
   bottom — returned **9223372036854775807**, the maximum *positive* value. A
   confident, plausible, maximally-wrong number where FPC returns the caller's
   default. Silent-wrong-value class.

3. **`TryStrToInt` trimmed and the others did not**, so a trailing space was
   accepted or rejected depending on which function the caller happened to use.

Separately in the same area: **`IntToStr(Low(Int64))` returned a bare `'-'`.**
`if neg then value := -value` leaves `Low(Int64)` unchanged (it has no positive
counterpart), so the `while value > 0` digit loop never ran. Fixed by
accumulating digits on the negative side, where every in-range value is
representable — the same trick the new parser uses in the other direction.

## Fix

`lib/rtl/sysutils.pas`:

- new `ParseIntPrefixed`, the single parser all four entry points now call;
- exact overflow detection, split into two tests so neither can itself
  overflow, and accumulating negatively so `Low(Int64)` is reachable;
- `IntToStr` rewritten around the same negative accumulation.

Kept deliberately, because they are FPC's rules and look like bugs otherwise:
**32-bit overflow truncates** (`StrToIntDef('99999999999')` = 1215752191) while
**64-bit overflow rejects**. The asymmetry is FPC's, verified directly.

## Test

`test/lib_strtoint.pas`, 36 assertions, compiling under FPC with every
expectation read off an FPC build. Notably it asserts that **all four entry
points return the same thing** rather than checking one of them — testing a
single function could not have found the actual defect. 18 fail without the fix.
