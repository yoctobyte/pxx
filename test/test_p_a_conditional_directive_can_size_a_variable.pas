program test_p_a_conditional_directive_can_size_a_variable;
{ `{$if sizeof(aintmax) = 8}` is FPC's hlcgobj.pas:4156, and `aintmax` is a
  LOCAL VARIABLE of the enclosing procedure (hlcgobj.pas:4023), not a type. The
  sizeof arm resolved a TYPE NAME only and said so in its own comment, so the
  whole unit stopped there.

  THIS IS THE CONDITIONAL-DIRECTIVE SPELLING OF A FIX THAT ALREADY LANDED.
  a931bef4d fixed `sizeof(<a PARAMETER>)` on the EXPRESSION path --
  `array[0..sizeof(d)-1]`, entfile.pas:371. Same feature, different door, and
  neither the construct name nor the message distinguishes them, which is
  exactly the case CLAUDE.md says a grep for the construct will miss.

  THE COMMA LIST IS TESTED AT BOTH ENDS ON PURPOSE. A walk that found the name
  and then expected `:` immediately would answer for `a` in `a, b, c: longint`
  and decline for `c`; one that scanned backwards to the start of the list
  would do the opposite. IN_LIST_FIRST and IN_LIST_LAST fail on opposite bugs,
  so neither arrangement can certify the other.

  A FALSE ROW IS INCLUDED BECAUSE 8 IS A COLLIDING DEFAULT. A machinery that
  did nothing and answered a pointer width would satisfy every `= 8` row in
  this file; BYTE_IS_NOT_EIGHT is the row that separates a real answer from a
  plausible one.

  Byte-identical to fpc 3.2.2 on all 5 rows, measured. Sizes chosen to agree
  between the two compilers -- `extended` is deliberately absent, because ours
  is 8 and fpc's is 10 and that difference is chosen, not a defect. }
var fails: Integer;

procedure Check(const nm: AnsiString; got, want: Boolean);
begin
  if got = want then WriteLn(nm, '=', 'yes')
  else begin WriteLn(nm, '=NO'); Inc(fails); end;
end;

type
  tcgint = int64;
var
  plain: int64;
  viaalias: tcgint;
  la, lb, lc: longint;
  small: byte;

const
{ the variable's own declared type }
{$if sizeof(plain) = 8}
  VAR_DIRECT = True;
{$else}
  VAR_DIRECT = False;
{$endif}
{ ...and one more hop, through a type alias the source declares }
{$if sizeof(viaalias) = 8}
  VAR_VIA_ALIAS = True;
{$else}
  VAR_VIA_ALIAS = False;
{$endif}
{ FIRST of a comma list... }
{$if sizeof(la) = 4}
  IN_LIST_FIRST = True;
{$else}
  IN_LIST_FIRST = False;
{$endif}
{ ...and LAST of the same list, which fails on the opposite bug }
{$if sizeof(lc) = 4}
  IN_LIST_LAST = True;
{$else}
  IN_LIST_LAST = False;
{$endif}
{ the row that cannot pass by accident }
{$if sizeof(small) = 8}
  BYTE_IS_NOT_EIGHT = False;
{$else}
  BYTE_IS_NOT_EIGHT = True;
{$endif}

begin
  fails := 0;
  plain := 0; viaalias := 0; la := 0; lb := 0; lc := 0; small := 0;
  Check('VAR_DIRECT', VAR_DIRECT, True);
  Check('VAR_VIA_ALIAS', VAR_VIA_ALIAS, True);
  Check('IN_LIST_FIRST', IN_LIST_FIRST, True);
  Check('IN_LIST_LAST', IN_LIST_LAST, True);
  Check('BYTE_IS_NOT_EIGHT', BYTE_IS_NOT_EIGHT, True);
  WriteLn('fails=', fails, ' ', plain + viaalias + la + lb + lc + small);
  WriteLn('CONDVARSIZE OK');
end.
