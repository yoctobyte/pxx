program test_variant_empty_renders_as_pascal_empty;
{ An empty Variant used to render as `None` in a PASCAL program -- NilPy's word
  for VT_EMPTY leaking into Pascal output through a renderer both frontends
  share. fpc 3.2.2 prints and casts an Unassigned as the EMPTY string; every
  row below is byte-identical to its output, diffed rather than reasoned about.
  bug-a-a-null-variant-renders-as-none-in-pascal

  pxx spells Null and Unassigned with one tag (documented in
  lib/rtl/variants.pas), and FPC RAISES EVariantTypeCastError for Null in both
  contexts -- so the empty string is the answer for the one spelling the two
  implementations can agree on, and the Null half is the `decide-` question,
  not this test's business.

  The non-empty rows are not filler: the Pascal renderer delegates to the
  shared one for every other tag, and they are what catches a delegation that
  stopped delegating. Boolean earns its place twice over -- it is the tag the
  two renderers most recently disagreed about
  (bug-a-a-boolean-variant-writes-as-1-or-0-off-x86-64). }
{$mode objfpc}{$H+}
uses variants;
var a: Variant; s: AnsiString;
begin
  a := Unassigned; WriteLn('write   [', a, ']');
  a := Unassigned; WriteLn('cast    [', string(a), ']');
  a := Unassigned; s := a; WriteLn('assign  [', s, '] ', Length(s));
  { concatenation reaches the same renderer by a third route }
  a := Unassigned; s := 'x' + string(a) + 'y'; WriteLn('concat  [', s, ']');

  a := 5;     WriteLn('int     [', a, '] [', string(a), ']');
  a := -7;    WriteLn('negint  [', a, '] [', string(a), ']');
  a := 'ss';  WriteLn('str     [', a, '] [', string(a), ']');
  a := True;  WriteLn('bool    [', a, '] [', string(a), ']');
  a := False; WriteLn('boolf   [', a, '] [', string(a), ']');
  a := 'c';   WriteLn('char    [', a, '] [', string(a), ']');
end.
