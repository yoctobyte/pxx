program test_for_in_picks_the_enumerator_that_fits_the_loop_variable;
{$mode objfpc}
{ A container can carry BOTH a `GetEnumerator` method and an
  `operator enumerator`, and fpc 3.2.2 chooses between them by the LOOP
  VARIABLE'S type. pxx took GetEnumerator unconditionally, which read the other
  enumerator's Current through the wrong type: measured 2026-09-07, this program
  printed `str1 str2` then `-1411383224 -1411383120` where fpc prints `1 2`.
  Exit 0 and plausible-looking numbers -- a SILENT wrong answer, which is the
  shape tforin24 reports over a TStrings iterated once into a String and once
  into an object.

  ROWS 3 AND 4 ARE THE POINT OF THE FILE AS MUCH AS ROWS 1-2. They are
  containers with only ONE mechanism each, so they pin the two arms that must
  keep working: a selection rule is easy to write in a way that fixes the
  two-enumerator case and quietly breaks every container that has just one, and
  neither row would notice if the other were the only test.

  Whole file matches fpc 3.2.2 exactly; the PINNED compiler prints garbage for
  row 2, so the fixture cannot pass by doing nothing. }
type
  TIntEnum = class
    i: Integer;
    function MoveNext: Boolean;
    property Current: Integer read i;
  end;

  TStrEnum = class
    n: Integer;
    function GetCurrent: string;
    function MoveNext: Boolean;
    property Current: string read GetCurrent;
  end;

  TBoth = class                        { GetEnumerator yields STRINGS... }
    function GetEnumerator: TStrEnum;
  end;

  TOnlyGet = class                     { ...only a GetEnumerator }
    function GetEnumerator: TStrEnum;
  end;

  TOnlyOp = class                      { ...only an operator enumerator }
    unused: Integer;
  end;

function TIntEnum.MoveNext: Boolean; begin Inc(i); MoveNext := i <= 2; end;
function TStrEnum.GetCurrent: string; begin GetCurrent := 'str' + Chr(48 + n); end;
function TStrEnum.MoveNext: Boolean; begin Inc(n); MoveNext := n <= 2; end;

function TBoth.GetEnumerator: TStrEnum; begin GetEnumerator := TStrEnum.Create; end;
function TOnlyGet.GetEnumerator: TStrEnum; begin GetEnumerator := TStrEnum.Create; end;

operator enumerator(b: TBoth): TIntEnum;      { ...and the operator yields INTEGERS }
begin Result := TIntEnum.Create; Result.i := 0; end;

operator enumerator(o: TOnlyOp): TIntEnum;
begin Result := TIntEnum.Create; Result.i := 0; end;

var
  b: TBoth;
  g: TOnlyGet;
  o: TOnlyOp;
  s: string;
  k: Integer;
begin
  b := TBoth.Create;
  for s in b do WriteLn('bothS ', s);    { the String loop var -> GetEnumerator }
  for k in b do WriteLn('bothK ', k);    { the Integer loop var -> the OPERATOR }

  g := TOnlyGet.Create;
  for s in g do WriteLn('onlyG ', s);    { one mechanism: must still be taken }

  o := TOnlyOp.Create;
  for k in o do WriteLn('onlyO ', k);    { ...and the other }
end.
