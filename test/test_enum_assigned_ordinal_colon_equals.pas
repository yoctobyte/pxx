{ Explicit enum ordinals written FPC's objfpc way -- `(ms_on := 1, ms_off := 2)`
  -- were refused; only the Delphi `=` spelling parsed. One concept, two surface
  tokens, so both are accepted UNCONDITIONALLY rather than behind a mode switch
  (normalise-dont-special-case: a second path for the same thing is the smell).
  FPC splits them by mode, which means we accept a form FPC rejects in the other
  mode; per the FPC-parity ceiling in CLAUDE.md that is explicitly not a defect.

  This was the wall on FPC's own compiler/globtype.pas (tmsgstate, line 800),
  which is why the ticket is Track P rather than cosmetic.

  Oracled against `fpc -Mobjfpc` 3.2.2, which accepts every row below including
  the MIXED declaration -- the two spellings may be interleaved in one list.
  feature-p-fpc-assigned-enum-ordinals-with-colon-equals }
program test_enum_assigned_ordinal_colon_equals;

type
  { FPC compiler/globtype.pas:800, verbatim in shape: assignments, a hole, and
    an unvalued member that must continue from the previous value + 1. }
  tmsgstate = (ms_on := 1, ms_off := 2, ms_error := 3, ms_warn, ms_fatal := 10);
  TDelphi   = (d_a = 5, d_b = 7, d_c);
  TMixed    = (m_a := 2, m_b = 4, m_c);
  { hex values, as globtype spells its global half }
  THexed    = (h_lo := $11, h_mid := $22, h_hi := $33);

var
  m: tmsgstate;
  d: TDelphi;
  x: TMixed;
  h: THexed;

begin
  m := ms_warn;  d := d_c;  x := m_c;  h := h_mid;

  writeln(Ord(ms_on), ' ', Ord(ms_off), ' ', Ord(ms_error), ' ',
          Ord(ms_warn), ' ', Ord(ms_fatal));
  writeln(Ord(d_a), ' ', Ord(d_b), ' ', Ord(d_c));
  writeln(Ord(m_a), ' ', Ord(m_b), ' ', Ord(m_c));
  writeln(Ord(h_lo), ' ', Ord(h_mid), ' ', Ord(h_hi));
  writeln(Ord(m), ' ', Ord(d), ' ', Ord(x), ' ', Ord(h));

  { the value carries its enum IDENTITY, not just an ordinal -- the `:=` form
    must go through the same AddEnumVal path the `=` form does }
  writeln(m = ms_warn, ' ', m = ms_on);
  writeln(h > h_lo, ' ', h < h_hi);
end.
