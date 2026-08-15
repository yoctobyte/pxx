{$mode objfpc}
{ `for x in [...]` where the LOOP VARIABLE is NOT ordinal.

  test_forin_literal_sources beside this one pins the SET reading: with an
  ordinal loop variable `[5,1,3,2]` is a set and FPC iterates it in ORDINAL
  order. That is only half the rule. **FPC decides the bracket list's kind from
  the variable it is iterating into, not from the elements** — with a
  non-ordinal variable the same syntax is an ARRAY CONSTRUCTOR, iterated in
  SOURCE order. The `['b','a']` rows below are the proof: the identical literal
  gives `a b` into a Char and `b a` into an AnsiString.

  pxx keyed on the ELEMENT type and had no non-ordinal arm at all, so a float
  constructor was built as a SET of float bits: `for d in [1.5, 2.5, 3.5]` ran
  ONCE and bound 0.0 — the count and every value lost — while the integer, char
  and `array of Double` forms beside it were right, and a string constructor did
  not compile at all.
  bug-p-for-in-over-a-float-array-constructor-iterates-once-with-zero

  Every expected value below was taken from FPC 3.2.2 on this same source,
  except the one row noted as a deliberate divergence. }
program test_forin_nonordinal_array_ctor;
var
  d: Double;
  s: AnsiString;
  c: Char;
  i: Integer;
  n: Integer;
  a: array of Double;
  lo, hi: Double;
begin
  { the defect: source order, all elements, right values }
  Write('float3: '); for d in [1.5, 2.5, 3.5] do Write(d:0:2, ' '); WriteLn;
  Write('float1: '); for d in [1.5] do Write(d:0:2, ' '); WriteLn;
  Write('floatr: '); for d in [3.5, 1.5, 2.5] do Write(d:0:2, ' '); WriteLn;

  { the count was 1 for any length — assert it separately from the values }
  n := 0; for d in [1.5, 2.5, 3.5] do Inc(n); WriteLn('count: ', n);

  { built from VARIABLES, not just literals }
  lo := 0.5; hi := 9.25;
  Write('fvars : '); for d in [lo, hi, lo] do Write(d:0:2, ' '); WriteLn;

  { a string constructor did not compile. Every element is deliberately MULTI-
    character: FPC types a single-char literal in this position as a Char and
    prints `f?` for `'f'` — a second, unrelated FPC quirk that would only muddy
    the oracle here. }
  Write('strs  : '); for s in ['abc', 'de', 'fg'] do Write(s, ' '); WriteLn;

  { THE RULE, both ways round: one literal, two readings, chosen by the
    loop variable. Ordinal => set, ordinal order. Non-ordinal => array,
    source order. }
  Write('char  : '); for c in ['b', 'a'] do Write(c, ' '); WriteLn;
  Write('str   : '); for s in ['b', 'a'] do Write(s, ' '); WriteLn;

  { the ordinal controls, unchanged }
  Write('ints  : '); for i in [5, 1, 3, 2] do Write(i, ' '); WriteLn;

  { and the dynamic array of Double, which was always right }
  SetLength(a, 3); a[0] := 1.5; a[1] := 2.5; a[2] := 3.5;
  Write('dynarr: '); for d in a do Write(d:0:2, ' '); WriteLn;

  { DELIBERATE DIVERGENCE. FPC 3.2.2 prints `1.00 0.00` here: its mixed
    integer/float constructor drops the 2.5. pxx answers 2.50. Not copied —
    losing a written value is a defect, not a semantic choice, and the whole
    point of this ticket was a constructor that silently answered zero.
    Recorded rather than hidden: decide-forin-mixed-int-float-ctor-vs-fpc. }
  Write('mixed : '); for d in [1, 2.5] do Write(d:0:2, ' '); WriteLn;
end.
