program test_conv_op_rank_literal_by_value;
{ Which `operator :=` an untyped integer CONSTANT selects.

  fpc 3.2.2 types the constant FIRST, by its VALUE -- the smallest type that
  holds it, signed candidate before unsigned at each width -- and only then
  ranks the conversion operators against that type. pxx typed every literal
  Integer and ranked THAT, so `d := 200` took `operator :=(Int64)` where fpc
  takes `operator :=(Byte)`.

  Three separate defects have to be fixed for this file to pass, and each block
  below is the row that isolates one of them. All output is fpc 3.2.2's own
  (bug-p-conversion-operator-ranking-reads-a-literals-static-kind-not-its-value).

  It asserts the LADDER and not a single row on purpose: "narrowest fitting type
  wins" gets 200 right and 5 wrong, so a fixture built from the one row the
  ticket recorded would have certified a wrong rule. }
{$mode objfpc}{$H+}

type
  { The full ladder: every rung declared, so each value hits an EXACT match. }
  TAll = record w: AnsiString; end;
  { Two candidates, declared in each order, to show the tie-break. }
  TFwd = record w: AnsiString; end;
  TRev = record w: AnsiString; end;
  { Integer against LongInt: the same type spelled two ways. }
  TAlias = record w: AnsiString; end;

operator := (a: ShortInt): TAll; begin Result.w := 'ShortInt'; end;
operator := (a: Byte): TAll;     begin Result.w := 'Byte'; end;
operator := (a: SmallInt): TAll; begin Result.w := 'SmallInt'; end;
operator := (a: Word): TAll;     begin Result.w := 'Word'; end;
operator := (a: LongInt): TAll;  begin Result.w := 'LongInt'; end;
operator := (a: Int64): TAll;    begin Result.w := 'Int64'; end;

operator := (a: SmallInt): TFwd; begin Result.w := 'SmallInt'; end;
operator := (a: Int64): TFwd;    begin Result.w := 'Int64'; end;

operator := (a: Int64): TRev;    begin Result.w := 'Int64'; end;
operator := (a: SmallInt): TRev; begin Result.w := 'SmallInt'; end;

operator := (a: Int64): TAlias;   begin Result.w := 'Int64'; end;
operator := (a: LongInt): TAlias; begin Result.w := 'LongInt'; end;

const
  K200 = 200;
  KNEG = -5;
  KSUM = 100 + 156;

var
  a: TAll;
  f: TFwd;
  r: TRev;
  x: TAlias;
  i: Integer;
  q: QWord;

begin
  { (1) THE LADDER. Signed before unsigned at each width, which is why 5 is a
    ShortInt and 128 is a Byte -- not "the narrowest that holds it". }
  a := 5;      writeln('5 -> ', a.w);
  a := 127;    writeln('127 -> ', a.w);
  a := 128;    writeln('128 -> ', a.w);
  a := 200;    writeln('200 -> ', a.w);
  a := 255;    writeln('255 -> ', a.w);
  a := 256;    writeln('256 -> ', a.w);
  a := 32767;  writeln('32767 -> ', a.w);
  a := 32768;  writeln('32768 -> ', a.w);
  a := 65535;  writeln('65535 -> ', a.w);
  a := 65536;  writeln('65536 -> ', a.w);

  { A NEGATIVE constant is a different NODE SHAPE, not just a different value:
    unary minus over a constant is not a literal node, so a fix that keys on
    "is this an integer-literal node" passes every row above and fails these
    two. `0-1` folds and does NOT discriminate -- it is here as the control
    that shows the two shapes give one answer. }
  a := -1;     writeln('-1 -> ', a.w);
  a := -200;   writeln('-200 -> ', a.w);
  a := 0-1;    writeln('0-1 -> ', a.w);

  { A named const and a folded const EXPRESSION type by value too. }
  a := K200;   writeln('K200 -> ', a.w);
  a := KNEG;   writeln('KNEG -> ', a.w);
  a := KSUM;   writeln('KSUM -> ', a.w);
  a := 100+156; writeln('100+156 -> ', a.w);

  { (2) THE TIE-BREAK IS DECLARATION ORDER. Identical candidate sets, opposite
    declaration order, opposite answers -- so it cannot be width and it cannot
    be a refusal. pxx used to report `more than one conversion operator applies`
    for both. 300 is the control: it types SmallInt, matches exactly, and the
    order stops mattering. }
  f := 5;      writeln('fwd 5 -> ', f.w);
  r := 5;      writeln('rev 5 -> ', r.w);
  f := 300;    writeln('fwd 300 -> ', f.w);
  r := 300;    writeln('rev 300 -> ', r.w);

  { (3) `Integer` AND `LongInt` ARE ONE TYPE. Int64 is declared FIRST, so if
    exactness did not see through the spelling this would answer Int64 by the
    order rule above -- the two fixes have to be in place together for this row
    to be right, and each alone gets it wrong. }
  i := 5;
  x := i;      writeln('Integer var -> ', x.w);
  x := 65536;  writeln('65536 -> ', x.w);

  { A literal above High(Int64) is already tagged QWord and must KEEP that kind:
    the value ladder takes an Int64 and would read this one as -1. }
  q := 18446744073709551615;
  writeln('qword literal -> ', q);
end.
