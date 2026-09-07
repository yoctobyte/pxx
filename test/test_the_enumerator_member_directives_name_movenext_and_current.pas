program test_the_enumerator_member_directives_name_movenext_and_current;
{ FPC lets a type NOMINATE which members play the for-in protocol:

    function StepForward: Boolean;      enumerator MoveNext;
    property Value: TObject read GetV;  enumerator Current;

  so a container's enumerator can be spelled in its own vocabulary and still be
  iterable. pxx refused the directive outright -- `expected 'end' before
  'enumerator'` on an interface, `expected ':' before 'MoveNext'` on a class or
  record, because an unconsumed `enumerator` reads as a field name.

  FOUR DECLARATION SITES, WHICH IS THE WHOLE REASON THIS FIXTURE IS SHAPED LIKE
  A GRID. An interface parses its methods and properties in one loop, a class in
  another, and a record has a THIRD method parser and a FOURTH property parser.
  Wiring one arm at a time, each of the four was discovered by the next probe
  failing -- none by reading the code. A test carrying only tforin9's interface
  would have passed with three of the four still broken.

  THE LAST TWO ROWS ARE THE GUARD, AND THEY MUST NOT BE DROPPED. `enumerator` is
  NOT a reserved word: a field, a variable or a method may be called that, and
  real code does. The directive is therefore recognised only where an identifier
  and a ';' follow it, and these rows fail if that guard is ever loosened into
  "the word `enumerator` starts a directive".

  Oracle: fpc 3.2.2 prints all eight rows exactly as below. The pinned compiler
  REFUSES this file at line 32 -- it has no directive at all. }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  { ---- an INTERFACE naming its own protocol: tforin9's shape ---- }
  IMyIter = interface
    function GetValue: LongInt;
    function StepForward: Boolean; enumerator MoveNext;
    property Value: LongInt read GetValue; enumerator Current;
  end;

  TIntfIter = class(TInterfacedObject, IMyIter)
  private
    FV: LongInt;
    function GetValue: LongInt;
  public
    function StepForward: Boolean;
    property Value: LongInt read GetValue;
  end;

  { ---- a CLASS naming its own protocol ---- }
  TClassIter = class
  private
    FV: LongInt;
    function Fetch: LongInt;
  public
    function Advance: Boolean; enumerator MoveNext;
    property Item: LongInt read Fetch; enumerator Current;
  end;

  { ---- a RECORD naming its own protocol (third and fourth parsers) ---- }
  TRecIter = record
    FV: LongInt;
    function Step: Boolean; enumerator MoveNext;
    function Get: LongInt;
    property Val: LongInt read Get; enumerator Current;
  end;

  TIntfBag  = class public function GetEnumerator: IMyIter;    end;
  TClassBag = class public function GetEnumerator: TClassIter; end;
  TRecBag   = class public function GetEnumerator: TRecIter;   end;

  { ---- the guard: `enumerator` as an ordinary name ---- }
  TThing = class
  public
    enumerator: LongInt;
    function Doubled: LongInt;
  end;

function TIntfIter.GetValue: LongInt; begin Result := FV; end;
function TIntfIter.StepForward: Boolean; begin Inc(FV); Result := FV <= 2; end;

function TClassIter.Fetch: LongInt; begin Result := FV * 10; end;
function TClassIter.Advance: Boolean; begin Inc(FV); Result := FV <= 2; end;

function TRecIter.Step: Boolean; begin Inc(FV); Result := FV <= 2; end;
function TRecIter.Get: LongInt; begin Result := FV * 100; end;

function TIntfBag.GetEnumerator: IMyIter;    begin Result := TIntfIter.Create; end;
function TClassBag.GetEnumerator: TClassIter; begin Result := TClassIter.Create; end;
function TRecBag.GetEnumerator: TRecIter;     begin Result.FV := 0; end;

function TThing.Doubled: LongInt; begin Result := enumerator * 2; end;

var
  ib: TIntfBag; cb: TClassBag; rb: TRecBag; t: TThing;
  i: LongInt;
  enumerator: LongInt;
begin
  ib := TIntfBag.Create; cb := TClassBag.Create; rb := TRecBag.Create;

  for i in ib do WriteLn('intf ', i);
  for i in cb do WriteLn('class ', i);
  for i in rb do WriteLn('rec ', i);

  { the guard }
  t := TThing.Create; t.enumerator := 21;
  WriteLn('field ', t.Doubled);
  enumerator := 9;
  WriteLn('var ', enumerator);
end.
