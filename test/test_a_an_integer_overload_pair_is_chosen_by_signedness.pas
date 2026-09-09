program test_a_an_integer_overload_pair_is_chosen_by_signedness;
{$mode objfpc}
{ Two integer overloads that differ ONLY in signedness. pxx had no preference
  between them: OverloadArgRank ties every machine-int pair at rank 1 and
  MatchProcCall's Phase 1c2 returned the first chain match, so the answer was
  whichever arm was DECLARED FIRST -- and the negative rows were a wrong VALUE,
  not a wrong label (`-5 > 1000000` came out TRUE through the QWord arm).

  EVERY family appears TWICE, once in each declaration order (the `A` set is
  signed-first, the `B` set unsigned-first). That is the whole assertion: the
  two halves of each pair must print the SAME thing. A fixture in one order
  cannot fail this bug -- it measures the confounder held fixed, which is how
  the original ticket recorded pxx as agreeing with fpc on the Integer row.

  All three doors, because the selectors are three: MatchProcCall (free),
  FindUMethOverloadAhead (method) and FindUCtorOverloadArgs (constructor).

  THE POSITIVE CONTROL IS THE A/B PAIRING ITSELF: measured against the pinned
  pre-fix compiler, 13 of these 16 rows have the two halves DISAGREE and three
  print `qword BIG`, i.e. `-5 > 1000000` answered TRUE.

  The `expr`/`ecard`/`unry` rows are the opposite guard and they CANNOT fail
  this bug -- they read the same before and after. They are here so the rule
  cannot be passed by matching the SPELLED type: `cd + 0` is a signed
  expression however unsigned `cd` is, so those rows must print i64 while
  `card` prints qword. The `call`/`cast` rows are there for a third reason: the
  method probe parses arguments SPECULATIVELY and the committed loop re-parses
  them, so a rule that ranks on the probe's reading has to be checked on shapes
  where the two readings could differ, not only on a bare variable.

  Every row below is byte-identical to fpc 3.2.2 in both orders.
  compat-pascal-overload-prefers-signed-for-an-unsigned-argument }

type
  TCA = class
    Tag: AnsiString;
    function M(v: Int64): AnsiString; overload;
    function M(v: QWord): AnsiString; overload;
    constructor Create(v: Int64); overload;
    constructor Create(v: QWord); overload;
  end;
  TCB = class
    Tag: AnsiString;
    function M(v: QWord): AnsiString; overload;
    function M(v: Int64): AnsiString; overload;
    constructor Create(v: QWord); overload;
    constructor Create(v: Int64); overload;
  end;

function TCA.M(v: Int64): AnsiString; begin if v > 1000000 then M := 'i64 BIG' else M := 'i64'; end;
function TCA.M(v: QWord): AnsiString; begin if v > 1000000 then M := 'qword BIG' else M := 'qword'; end;
constructor TCA.Create(v: Int64); begin Tag := 'i64'; end;
constructor TCA.Create(v: QWord); begin Tag := 'qword'; end;

function TCB.M(v: QWord): AnsiString; begin if v > 1000000 then M := 'qword BIG' else M := 'qword'; end;
function TCB.M(v: Int64): AnsiString; begin if v > 1000000 then M := 'i64 BIG' else M := 'i64'; end;
constructor TCB.Create(v: QWord); begin Tag := 'qword'; end;
constructor TCB.Create(v: Int64); begin Tag := 'i64'; end;

{ free functions, signed declared first }
function SigA(v: Int64): AnsiString; overload;  begin if v > 1000000 then SigA := 'i64 BIG' else SigA := 'i64'; end;
function SigA(v: QWord): AnsiString; overload;  begin if v > 1000000 then SigA := 'qword BIG' else SigA := 'qword'; end;
{ ...and unsigned declared first }
function SigB(v: QWord): AnsiString; overload;  begin if v > 1000000 then SigB := 'qword BIG' else SigB := 'qword'; end;
function SigB(v: Int64): AnsiString; overload;  begin if v > 1000000 then SigB := 'i64 BIG' else SigB := 'i64'; end;

function FInt: Integer; begin FInt := -5; end;
function FCard: Cardinal; begin FCard := 5; end;

var
  a: TCA;
  b: TCB;
  si: Integer;
  cd: Cardinal;
  w: Word;
  by: Byte;
begin
  a := TCA.Create(Int64(0));
  b := TCB.Create(Int64(0));
  si := -5; cd := 5; w := 5; by := 5;

  WriteLn('free A byte  ', SigA(by),   '  B ', SigB(by));
  WriteLn('free A word  ', SigA(w),    '  B ', SigB(w));
  WriteLn('free A card  ', SigA(cd),   '  B ', SigB(cd));
  WriteLn('free A neg   ', SigA(si),   '  B ', SigB(si));

  WriteLn('meth A var   ', a.M(si),          '  B ', b.M(si));
  WriteLn('meth A card  ', a.M(cd),          '  B ', b.M(cd));
  WriteLn('meth A call  ', a.M(FInt),        '  B ', b.M(FInt));
  WriteLn('meth A ccall ', a.M(FCard),       '  B ', b.M(FCard));
  WriteLn('meth A expr  ', a.M(si + 0),      '  B ', b.M(si + 0));
  WriteLn('meth A ecard ', a.M(cd + 0),      '  B ', b.M(cd + 0));
  WriteLn('meth A cast  ', a.M(Integer(si)), '  B ', b.M(Integer(si)));
  WriteLn('meth A ccast ', a.M(Cardinal(cd)),'  B ', b.M(Cardinal(cd)));
  WriteLn('meth A unry  ', a.M(-cd),         '  B ', b.M(-cd));

  WriteLn('ctor A neg   ', TCA.Create(si).Tag,    '  B ', TCB.Create(si).Tag);
  WriteLn('ctor A card  ', TCA.Create(cd).Tag,    '  B ', TCB.Create(cd).Tag);
  WriteLn('ctor A call  ', TCA.Create(FCard).Tag, '  B ', TCB.Create(FCard).Tag);
end.
