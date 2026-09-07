program test_for_in_lowers_class_record_and_interface_enumerators_alike;
{ An enumerator reaches `for X in C` by TWO doors -- a GetEnumerator method and
  an `operator enumerator` -- and it can be one of THREE shapes: a class (a bare
  pointer), a record (an embedded VALUE), or an interface (a 16-byte fat pointer
  {IMT, instance}). That is six combinations and every one of them must lower to
  the same loop.

  WHY ALL SIX AND NOT THE TWO THAT WERE BROKEN. Measured 2026-09-07 against the
  pinned compiler: the interface shape SEGFAULTED through both doors, and the
  record shape ran ZERO ITERATIONS through the operator door while working
  perfectly through the GetEnumerator door -- the record fix (tforin25) had been
  made in one builder and not in its twin, and nothing failed, so nobody saw it.
  A test carrying only the shapes that were reported would have gone green on
  the same one-sided fix. The grid IS the assertion.

  Oracle: fpc 3.2.2 prints all twelve rows exactly as expected below.

  READ THE PINNED CONTROL CAREFULLY -- IT STOPS EARLY AND THEREFORE CERTIFIES
  NOTHING AFTER ROW 4. Pinned prints geClass/geRec and then SEGFAULTS on the
  first interface row, so it never reaches `opRec` at all; the zero-iteration
  break in the operator+record cell was measured on its own separate program,
  not read off this file's pinned run. A control that dies partway is evidence
  about the rows before the crash and silence about the rest. }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  { ---- shape 1: a class enumerator (a pointer) ---- }
  TClassIter = class
  private
    FV: LongInt;
    function GetCurrent: LongInt;
  public
    function MoveNext: Boolean;
    property Current: LongInt read GetCurrent;
  end;

  { ---- shape 2: a record enumerator (a value, advancedrecords) ---- }
  TRecIter = record
    FV: LongInt;
    function MoveNext: Boolean;
    function GetCurrent: LongInt;
    property Current: LongInt read GetCurrent;
  end;

  { ---- shape 3: an interface enumerator (a fat pointer) ---- }
  IIntfIter = interface
    function GetCurrent: LongInt;
    function MoveNext: Boolean;
    property Current: LongInt read GetCurrent;
  end;

  TIntfIter = class(TInterfacedObject, IIntfIter)
  private
    FV: LongInt;
    function GetCurrent: LongInt;
  public
    function MoveNext: Boolean;
    property Current: LongInt read GetCurrent;
  end;

  { Door A: containers exposing GetEnumerator. }
  TClassBag = class public function GetEnumerator: TClassIter; end;
  TRecBag   = class public function GetEnumerator: TRecIter;   end;
  TIntfBag  = class public function GetEnumerator: IIntfIter;  end;

  { Door B: containers with no method at all -- the operator supplies it. }
  TOpClassBag = class end;
  TOpRecBag   = class end;
  TOpIntfBag  = class end;

function TClassIter.GetCurrent: LongInt; begin Result := FV; end;
function TClassIter.MoveNext: Boolean; begin Inc(FV); Result := FV <= 3; end;

function TRecIter.MoveNext: Boolean; begin Inc(FV); Result := FV <= 3; end;
function TRecIter.GetCurrent: LongInt; begin Result := FV * 10; end;

function TIntfIter.GetCurrent: LongInt; begin Result := FV * 100; end;
function TIntfIter.MoveNext: Boolean; begin Inc(FV); Result := FV <= 3; end;

function TClassBag.GetEnumerator: TClassIter; begin Result := TClassIter.Create; end;
function TRecBag.GetEnumerator: TRecIter;     begin Result.FV := 0; end;
function TIntfBag.GetEnumerator: IIntfIter;   begin Result := TIntfIter.Create; end;

operator enumerator(b: TOpClassBag): TClassIter; begin Result := TClassIter.Create; end;
operator enumerator(b: TOpRecBag): TRecIter;     begin Result.FV := 0; end;
operator enumerator(b: TOpIntfBag): IIntfIter;   begin Result := TIntfIter.Create; end;

var
  cb: TClassBag; rb: TRecBag; ib: TIntfBag;
  ocb: TOpClassBag; orb: TOpRecBag; oib: TOpIntfBag;
  i: LongInt;
begin
  cb := TClassBag.Create; rb := TRecBag.Create; ib := TIntfBag.Create;
  ocb := TOpClassBag.Create; orb := TOpRecBag.Create; oib := TOpIntfBag.Create;

  { Door A -- GetEnumerator. Two rows per shape is enough to separate "ran" from
    "ran zero times", which is the failure the record shape actually had. }
  for i in cb do if i <= 2 then WriteLn('geClass ', i);
  for i in rb do if i <= 20 then WriteLn('geRec ', i);
  for i in ib do if i <= 200 then WriteLn('geIntf ', i);

  { Door B -- operator enumerator. }
  for i in ocb do if i <= 2 then WriteLn('opClass ', i);
  for i in orb do if i <= 20 then WriteLn('opRec ', i);
  for i in oib do if i <= 200 then WriteLn('opIntf ', i);
end.
