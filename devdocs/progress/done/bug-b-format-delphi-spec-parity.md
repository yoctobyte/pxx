# SysUtils.Format parsed printf's spec, not Delphi's

- **Type:** bug — Track B (library), tag `compat` (FPC parity)
- **Status:** done
- **Resolved:** 2026-08-04 in `0ae0a4aa7` (verified on origin/master after the rebase)
- **Opened:** 2026-08-04
- **Found by:** widening `tools/fpc_diff_probe.sh` past its 40 core-language
  cases into sysutils. Three of the first 21 new cases diverged.

## Symptom

`Format` implemented C's `printf` grammar. Delphi's is a different grammar that
happens to look similar:

    %[index:][-][width][.prec]type          <- Delphi / FPC
    %[flags][width][.prec]type              <- printf

Diffed against FPC as the oracle:

| format | arg | FPC | pxx (before) |
| --- | --- | --- | --- |
| `%05d` | 42 | `   42` | `00042` |
| `%.3d` | 42 | `042` | `42` |
| `%8.3d` | 42 | `     042` | `      42` |
| `%.5d` | -42 | `-00042` | `-42` |
| `%.4x` | 255 | `00FF` | `FF` |
| `%x` | -1 | `FFFFFFFF` | `FFFFFFFFFFFFFFFF` |
| `%1:s-%0:s` | 'a','b' | `b-a` | `%:s-%:s` |

## Root causes — three, one parser

1. **A `0` flag that does not exist.** The parser consumed a leading `0` as
   printf's zero-pad flag. Delphi has no flags at all, so that zero is simply
   part of the *width*: `%05d` is "width 5", and width padding is *always*
   spaces. This is the one most likely to be hit by real code, because `%05d`
   is idiomatic C and reads as if it should work.

2. **Precision ignored for the integer types.** It was applied to `%s`, `%f`,
   `%g` and `%e` but not `%d`/`%u`/`%x`. For integers precision means a
   *minimum* digit count, zero-filled with the sign outside the fill
   (`%.5d` of -42 is `-00042`), and it never truncates — the opposite of `%s`,
   where precision is a ceiling. That asymmetry is why it reads like an
   oversight rather than a decision.

3. **`%x` of a 32-bit argument printed 64-bit.** `FmtArgInt` widens every
   argument to `Int64`, which is invisible for positive values and for `%d`,
   but sign-extends a negative one into sixteen nibbles. The original width is
   still recoverable from the variant tag, so `%x` now narrows back when
   `VType` says the argument was a plain `Integer`.

Argument indexes (`%1:s`) were not implemented at all, and are now — including
their cursor effect: a specifier after an indexed one continues from *there*,
so `Format('%1:s%s', ['a','b','c'])` is `bc`. Verified against FPC, which
raises `EConvertError` when that continuation runs off the end.

## Fix

`lib/rtl/sysutils.pas` — rewrote the specifier parse to the Delphi grammar,
added `FmtIntPrec` (integer zero-fill, sign preserved) and `FmtArgIs32`.
`FmtPad` lost its `zeroPad` parameter rather than keeping a dead one; it had a
single caller.

## Test

`test/lib_format.pas`, 14 -> 27 assertions. **The old file asserted the printf
reading of `%05d` and so pinned the bug in place** — that expectation was
written from C habit, not from the oracle, which is exactly how a wrong
expectation survives review. Every expectation in it is now taken from FPC.
12 of the 27 fail without the fix.

## Not fixed (out of scope, separate parity item)

FPC raises `EConvertError` when a format string asks for more arguments than
were passed; pxx substitutes an empty string. That divergence predates this
ticket and applies to plain `%s` too, so it is not part of the grammar fix.
