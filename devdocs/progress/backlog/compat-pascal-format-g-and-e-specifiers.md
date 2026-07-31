---
summary: "compat: Format's %g ignores its precision and uses 15 digits where FPC uses 17; %e is not implemented at all"
type: bug
track: B
prio: 25
---

# `Format`'s `%g` and `%e` are not FPC's

- **Type:** compat (library / RTL — **Track B**, reference = FPC)
- **Opened:** 2026-07-31, splitting the leftovers out of
  [[bug-rtl-floattostr-caps-at-six-decimals-and-zeroes-small-values]] so that
  ticket could close on the part that mattered (a nonzero value printing as `0`).

## Measured, pxx vs an FPC-built copy of the same program

| call | pxx | FPC |
| --- | --- | --- |
| `Format('%g', [1/3])` | `0.333333333333333` | `0.33333333333333331` |
| `Format('%.3g', [1/3])` | `0.333333333333333` | `0.333` |
| `Format('%e', [1/3])` | `%e` — emitted literally | `3.3333333333333331E-001` |
| `Format('%.4e', [1/3])` | `%e` — emitted literally | `3.333E-001` |
| `Format('%g', [12345.6789])` | `12345.6789` | `12345.6789` |
| `Format('%f', [1/3])` | `0.33` | `0.33` |
| `Format('%.15f', [1/3])` | `0.333333333333333` | `0.333333333333333` |

The `%f` rows are correct and stay correct — the explicitly-requested-precision
paths are the contract, and they are honoured.

## What is actually wrong

`lib/rtl/sysutils.pas`, the `'g'` branch of `Format`:

```pascal
'g':
  begin
    if argIdx < Length(args) then piece := FloatToStr(FmtArgFloat(args[argIdx]));
    Inc(argIdx);
  end;
```

Two things follow from that one line:

1. **`hasPrec`/`prec` are ignored.** Every other float spec consults them;
   `%.3g` and `%g` produce the same string.
2. **The digit count is `FloatToStr`'s.** That is FPC's `ffGeneral` with 15
   significant digits — the right rule for `FloatToStr`, and *not* the rule FPC
   applies to `%g`, which comes out at 17. (Before 2026-07-31 this was six
   decimal places, so the gap was much larger; the FloatToStr fix moved `%g`
   from wrong-by-nine-digits to wrong-by-two.)

`%e` never had a branch at all, so it falls to the `else` that emits an unknown
spec literally — a format string silently keeps `%e` in its output rather than
substituting the argument, and the argument index does not advance, which shifts
every following specifier.

## Shape

- `'g'`: take `prec` when `hasPrec` (default 15 for parity with FPC's `%g` needs
  checking against a wider oracle table first — measure, do not assume 17 is the
  whole rule), and render significant digits rather than deferring to
  `FloatToStr`.
- `'e'`: an exponential branch honouring `prec`. FPC's `%e` spelling is a
  THIRD one — `3.3333333333333331E-001`, a signed three-digit exponent —
  matching neither `FloatToExpStr`'s `E+nn` nor `FloatToStr`'s `Ennn`. Measured,
  not assumed.
- Whatever lands, the argument index must advance for every consumed specifier.

## Gate

`make lib-test`, plus a `.pas` diffed against an FPC build of the same file —
the way `test/lib_floattostr.pas` is built, where every expectation came from
the oracle rather than from reading pxx's own output back.
