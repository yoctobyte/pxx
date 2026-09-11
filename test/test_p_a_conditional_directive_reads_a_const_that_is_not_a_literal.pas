program test_p_a_conditional_directive_reads_a_const_that_is_not_a_literal;
{ `{$if}` could read a source `const` only when its value was an INTEGER
  LITERAL. FPC's rgobj.pas:1728 turns on a directive whose BOTH operands are
  something else, and it takes four separate hops to answer:

    RS_STACK_POINTER_REG = RS_RSP        a const naming another CONST, and the
                                         two live in DIFFERENT UNITS
                                         (x86_64/cpubase.inc:90 -> x86/cpubase.pas:84)
    RS_RSP               = $07           ...which is finally a literal
    RS_INVALID           = high(tsuperregister)   a FOLDED CALL
    TSuperRegister       = type word     ...over a DISTINCT-TYPE alias, which is
                                         four tokens and so fell outside the
                                         one-token alias shape (cgbase.pas:317)

  Every row below is a hop of that chain, spelled the way FPC spells it. The
  values are FPC's own: 65535 and 7.

  NO ROW HERE CAN PASS BY DOING NOTHING. 65535 is not a size, a default, a
  pointer width or a zero -- it is `high(word)` and nothing else answers it --
  and the two directive rows are asserted in BOTH directions, because an
  evaluator that resolved nothing answers False and would agree with half of a
  one-directional test. The `=` row exists for exactly that reason: it is the
  one a broken chain would get right for free.

  WHAT STILL DECLINES, and must: an enum, a record, a subrange, and a const
  cycle. Those cannot live in this file because they halt the compile; the
  cycle is pinned by a Makefile row beside this one, since it is the case where
  the failure mode would be a HANG rather than a diagnostic. }
type
  TSuper = type Word;
const
  RS_INV = high(TSuper);
  RS_LOW = low(TSuper);
  RS_RSP = $07;
  RS_SP  = RS_RSP;

{ The directive FPC actually writes, both arms asserted. }
{$if declared(RS_SP) and (RS_SP <> RS_INV)}
  DIFFERS = True;
{$else}
  DIFFERS = False;
{$endif}
{$if declared(RS_SP) and (RS_SP = RS_INV)}
  EQUALS = True;
{$else}
  EQUALS = False;
{$endif}
{ A second hop on the const side, so one level of chaining is not mistaken for
  arbitrary depth working. }
  RS_SP2 = RS_SP;
{$if RS_SP2 = 7}
  CHAINED = True;
{$else}
  CHAINED = False;
{$endif}

var fails: Integer;

procedure Check(const nm: AnsiString; got, want: Int64);
begin
  if got = want then WriteLn(nm, '=yes')
  else begin WriteLn(nm, '=NO got ', got, ' want ', want); Inc(fails); end;
end;

begin
  fails := 0;
  Check('high-over-distinct-alias', RS_INV, 65535);
  Check('low-over-distinct-alias', RS_LOW, 0);
  Check('const-names-a-const', RS_SP, 7);
  Check('two-hop-const-chain', RS_SP2, 7);
  Check('directive-differs-taken', Ord(DIFFERS), Ord(True));
  Check('directive-equals-not-taken', Ord(EQUALS), Ord(False));
  Check('directive-over-chained-const', Ord(CHAINED), Ord(True));
  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('CONDNONLIT OK') else WriteLn('CONDNONLIT FAIL');
end.
