---
track: N
prio: 60
type: bug
status: blocked
blocked-by: [decide-nilpy-where-the-exact-decimal-float-core-lives]
summary: "print(float) does not use Python's shortest-round-trip repr: 1/3 loses a digit, 0.1+0.2 prints 0.3 (hiding the error), 1e-20 prints WRONG DIGITS (1.000000000000001e-20), and the scientific-notation threshold differs (3e-05 vs 0.00003)"
status: working
owner: claude-AN-night
---

# Float printing is not Python's `repr` — six distinct divergences

- **Type:** bug (NilPy — SILENT wrong output) — **Track N**
- **Found:** 2026-08-02 by a differential sweep against the CPython oracle
  (`tools/pydiff.py`).

## Measured

```python
for v in [0.1, 1/3, 1e20, 1e-20, 2.0, -0.0, 100.0, 1.5e300, 3.0e-5, 123456789.123]:
    print(v)
print(0.1 + 0.2)
print(1/3 + 1/3)
```

| expression | CPython | pxx |
| --- | --- | --- |
| `1/3` | `0.3333333333333333` | `0.333333333333333` |
| `1/3 + 1/3` | `0.6666666666666666` | `0.666666666666667` |
| `1e-20` | `1e-20` | `1.000000000000001e-20` |
| `3.0e-5` | `3e-05` | `0.00003` |
| `123456789.123` | `123456789.123` | `123456789.122999995946884` |
| `0.1 + 0.2` | `0.30000000000000004` | `0.3` |

`0.1`, `1e20`, `2.0`, `-0.0`, `100.0`, `1.5e300`, `7/2`, `7//2`, `7.0//2` and
`float("inf")` / `float("-inf")` all agree.

## The four separate faults, because they need different fixes

1. **Digit count.** `0.333333333333333` is 15 significant digits; a double needs
   **17** to round-trip, and Python emits the *shortest* string that round-trips
   (16 here). One digit is being dropped, so the value does not round-trip.

2. **Wrong digits, not just fewer.** `1e-20` printing as `1.000000000000001e-20`
   is not a truncation — it is a different number. The conversion is producing
   noise digits in the small-exponent path.

3. **Scientific-notation threshold.** Python switches to exponent form for
   `abs(v) < 1e-4` (`3e-05`) and for `>= 1e16`. pxx printed `0.00003`, so the
   low-end threshold is absent or set elsewhere. Note also the **two-digit
   exponent** (`3e-05`, not `3e-5`), which is part of the format.

4. **Over-expansion.** `123456789.122999995946884` is the exact binary value
   printed to excess precision instead of the shortest round-tripping form.

`0.1 + 0.2` → `0.3` is the same root cause as (1) seen from the friendly side:
rounding to too few digits happens to hide the representation error. It is still
wrong against the oracle, and it is the one most likely to be mistaken for
correct behaviour.

## Why this matters more than it looks

Python's `repr` contract is *round-trip*: `float(repr(x)) == x` for every finite
double. Every divergence above breaks it, so any NilPy program that serialises
floats through `str`/`print` — JSON, CSV, a config dump, a test's expected
output — loses precision silently and asymmetrically. It also means a `.npy`
regression test whose expected output contains a float is currently recording
pxx's rounding, not CPython's.

## Where to look

The Python-facing float formatting path, not Pascal's `Str`/`WriteLn` — Pascal
has its own (correct for Pascal) conventions and must not change. Check whether
the NilPy `print` of a float routes through a shared Pascal float-to-string
helper; if it does, this needs a NilPy-specific formatter rather than a change
to the shared one, or Track P/A regressions follow.

The algorithm is the shortest-round-trip one (Steele & White / Grisu / Ryu).
Getting it exactly right for all doubles is real work; getting (2) and (3) right
— wrong digits and the threshold — is separable and worth doing first, since a
wrong digit is a worse failure than a suboptimal digit count.

## Related, found in the same sweep

`repr` is not defined as a builtin at all (`error: undefined variable (repr)`),
so the round-trip property cannot even be spelled from NilPy source today. See
[[bug-nilpy-unsupported-protocols-repr-iter-getattr-delitem-hash]] for the
dunder side of that.

## Gate

A `.npy` diffed against CPython over a table of doubles covering: the six rows
above, both notation thresholds from either side (`1e-4`, `9.9e-5`, `1e16`,
`9.9e15`), negatives, subnormals, `float('inf')` / `-inf` / `nan`, and a
round-trip assertion `float(str(x)) == x` over the whole table.


## 2026-08-03 — the formatter is WRITTEN and measured; it is blocked on layering

The Python side is done. What stopped it is where two numeric routines live, not
anything about Python — filed as
[[decide-nilpy-where-the-exact-decimal-float-core-lives]].

### What was established

Python's repr is the SHORTEST decimal that reads back as the same double, and
the way to get that right is not a digit-count heuristic: try precisions 1..17
and CHECK the round trip, so the answer is correct by construction. That needs
exact decimal digits and a correctly-rounded parser.

**Both already exist**, in `lib/rtl/sysutils.pas`: `ExDecDigits` / `ExDecRound`
/ `FloatToStrExact` / `StrToFloat`, and `FloatToStrShortest` is already this
exact loop with PASCAL's layout. Nothing needs inventing.

**But `PyFloatStr` lives in `compiler/builtin/pylib.pas`, and a builtin unit may
not `uses sysutils`** — the rule `compiler/builtin/promoint.pas` states and
follows (it reimplemented bignum rather than use `lib/rtl/bignum.pas`).
Measured, not assumed: `PXXDBG=a.ir:FloatToStrExact` on a `print(1)` program
dumps nothing, so a trivial `.npy` does not link sysutils today and pylib using
it really would add it to every NilPy binary.

`builtin.pas`'s own `FloatToStr` uses `Trunc`/`Frac` scaled to 15 decimal
places, which is the direct cause of all six divergences above.

### The three layout rules, since they are the part that is easy to get wrong

- exponential iff `decpt <= -4` or `decpt > 16`, where `decpt = decExp + 1` —
  NOT Pascal's `[-3, sig]` window, which also moves with the requested
  precision, so `ExDecLayout` cannot be reused;
- fixed form ALWAYS shows a point (`2.0`, `100.0` — CPython's
  `Py_DTSF_ADD_DOT_0`);
- the exponent is signed with at LEAST two digits: `3e-05`, `1e+16`, and
  `1.5e+300` (no padding past two).

Checked by hand against every row of the table above plus both thresholds from
either side (`1e-4` -> `0.0001`, `9.9e-5` -> `9.9e-05`, `9.9e15` ->
`9900000000000000.0`, `1e16` -> `1e+16`).

### Ready to apply

The code below drops into `pylib.pas` in place of `PyFloatStr`'s body the
moment `FloatToStrExact` / `StrToFloat` are reachable from a builtin unit. It
compiled; the only error left was `undefined variable (FloatToStrExact)`, i.e.
exactly the blocker. (`IntToStr` is likewise not available there — pylib's
integer-to-string is `StrInt(n, 0)`, already used below.)

```pascal
{ Split FloatToStrExact's output for a POSITIVE finite value into Python's two
  ingredients: `digits`, the significant digits with no point and no leading or
  trailing zeros, and `decExp`, the power of ten the FIRST digit carries
  (value = d.ddd * 10^decExp).

  Parsing a string this unit just produced, rather than reaching for sysutils'
  internal ExDecDigits: those are implementation-only, and exporting them to
  give NilPy a Python-shaped formatter would put a Python rule in the Pascal
  RTL's interface. The output format is fixed and small — an optional
  `E<exp>` tail, an optional point, leading zeros — so this stays a few lines.
  Every result is round-trip CHECKED by the caller regardless. }
procedure PyFloatSplit(const s: AnsiString; var digits: AnsiString; var decExp: Integer);
var i, dot, intLen, expPart, lead, tail, esign: Integer; mant, all: AnsiString;
begin
  digits := '0'; decExp := 0;
  mant := s; expPart := 0;
  for i := 1 to Length(s) do
    if (s[i] = 'E') or (s[i] = 'e') then
    begin
      mant := Copy(s, 1, i - 1);
      esign := 1;
      dot := i + 1;
      if (dot <= Length(s)) and ((s[dot] = '-') or (s[dot] = '+')) then
      begin
        if s[dot] = '-' then esign := -1;
        dot := dot + 1;
      end;
      expPart := 0;
      while dot <= Length(s) do
      begin
        expPart := expPart * 10 + (Ord(s[dot]) - Ord('0'));
        dot := dot + 1;
      end;
      expPart := expPart * esign;
      Break;
    end;
  dot := 0;
  for i := 1 to Length(mant) do
    if mant[i] = '.' then begin dot := i; Break; end;
  if dot = 0 then intLen := Length(mant) else intLen := dot - 1;
  all := '';
  for i := 1 to Length(mant) do
    if mant[i] <> '.' then all := all + mant[i];
  lead := 0;
  while (lead < Length(all)) and (all[lead + 1] = '0') do lead := lead + 1;
  all := Copy(all, lead + 1, Length(all) - lead);
  if all = '' then begin digits := '0'; decExp := 0; Exit; end;
  decExp := intLen - 1 - lead + expPart;
  tail := Length(all);
  while (tail > 1) and (all[tail] = '0') do tail := tail - 1;
  digits := Copy(all, 1, tail);
end;

{ Lay `digits` / `decExp` out the way CPython's repr does. The rule is one
  comparison on `decpt`, the position of the decimal point: exponential when
  `decpt <= -4` or `decpt > 16`, fixed otherwise — which is NOT Pascal's
  window ([-3, sig], and dependent on the requested precision), so it cannot be
  borrowed from ExDecLayout.

  Two details that are part of the format and easy to miss: a fixed-form float
  always shows a point (`2.0`, `100.0` — Python's Py_DTSF_ADD_DOT_0), and the
  exponent is signed with at LEAST two digits (`3e-05`, `1e+16`, but
  `1.5e+300`). }
function PyFloatLayout(const digits: AnsiString; decExp: Integer): AnsiString;
var decpt, i, ae: Integer; s, es: AnsiString;
begin
  decpt := decExp + 1;
  if (decpt <= -4) or (decpt > 16) then
  begin
    s := Copy(digits, 1, 1);
    if Length(digits) > 1 then s := s + '.' + Copy(digits, 2, Length(digits) - 1);
    if decExp < 0 then begin s := s + 'e-'; ae := -decExp; end
    else begin s := s + 'e+'; ae := decExp; end;
    es := StrInt(ae, 0);
    if Length(es) < 2 then es := '0' + es;
    Result := s + es;
  end
  else if decpt <= 0 then
  begin
    s := '0.';
    for i := 1 to -decpt do s := s + '0';
    Result := s + digits;
  end
  else if decpt >= Length(digits) then
  begin
    s := digits;
    for i := Length(digits) + 1 to decpt do s := s + '0';
    Result := s + '.0';
  end
  else
    Result := Copy(digits, 1, decpt) + '.' + Copy(digits, decpt + 1, Length(digits) - decpt);
end;

{ Python's `repr` of a float: the SHORTEST decimal string that reads back as
  the same double, laid out by Python's rules.

  Shortest is found by trying precisions and CHECKING the round trip, so the
  result is correct by construction rather than by trusting a digit-count
  heuristic — the same method sysutils' FloatToStrShortest uses, with Python's
  layout instead of Pascal's. 17 significant digits always round-trip a double,
  so the loop terminates.

  Returns '' when the value is not finite-nonzero or when nothing round-tripped;
  the caller handles those. }
function PyFloatRepr(av: Double): AnsiString;
var sig: Integer; digits, cand: AnsiString; decExp: Integer;
begin
  Result := '';
  for sig := 1 to 17 do
  begin
    PyFloatSplit(FloatToStrExact(av, sig), digits, decExp);
    cand := PyFloatLayout(digits, decExp);
    if StrToFloat(cand) = av then begin Result := cand; Exit; end;
  end;
end;

function PyFloatStr(d: Double): AnsiString;
var bits: Int64; av: Double; rep: AnsiString;
begin
  { Python's repr, not Pascal's FloatToStr. FloatToStr is FPC's fifteen
    SIGNIFICANT digits with FPC's own fixed/exponential window, and it is
    correct for Pascal and observable by every Pascal program in the tree — so
    it is not changed; NilPy gets its own formatter instead. Six measured
    divergences it removes, all silent: 1/3 lost a digit and stopped
    round-tripping, 0.1+0.2 printed 0.3 (the representation error HIDDEN by
    rounding, the one most likely to be read as correct), 1e-20 printed
    1.000000000000001e-20 (different digits, not fewer), 3.0e-5 printed
    0.00003 instead of 3e-05, and 123456789.123 expanded to
    123456789.122999995946884
    (bug-nilpy-float-repr-is-not-pythons-shortest-roundtrip). }
  av := d;
  if av < 0 then av := -av;
  if (d = d) and (av <= 1.7976931348623157e308) and (d <> 0) then
  begin
    rep := PyFloatRepr(av);
    if rep <> '' then
    begin
      if d < 0 then Result := '-' + rep else Result := rep;
      Exit;
    end;
  end;
  Result := FloatToStr(d);
```

### Also worth keeping

`str(float)` and `repr(float)` are the same function in Python 3, so one
formatter serves both — but `repr` is not even defined as a builtin in NilPy
yet ([[bug-nilpy-unsupported-protocols-repr-iter-getattr-delitem-hash]]), so the
round-trip property cannot be spelled from NilPy source. The gate's
`float(str(x)) == x` assertion needs that ticket first, or has to be written as
a comparison against a literal table.
