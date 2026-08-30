program test_property_in_an_interface;
{ A PROPERTY declared inside an INTERFACE — read, write, and indexed read.

  Two defects in one shape, and the first hid the second. The parser stopped an
  interface's member loop at `procedure`/`function` only, so `property` there
  was "expected 'end' before 'property'" — fcl-xml's DOM is built out of such
  interfaces, and that was rung 3 of the OOP corpus. With parsing fixed the
  program compiled and then SEGFAULTED, because the eleven hand-written copies
  of "how is a property accessor dispatched" all knew exactly two answers,
  AN_VIRTUAL_CALL and AN_CALL, and an interface receiver needs the third:
  AN_INTF_CALL, whose Self comes from the fat pointer rather than argument 0.
  The ordinary call `i.GetV` already had that arm; the property path, being a
  separate copy, did not — so it read a class VMT off an interface value.

  The `direct` row is the control: it takes the arm that already worked, so a
  regression that breaks interface dispatch generally fails BOTH rows and is
  distinguishable from one that breaks only properties. The indexed row is
  there because an index argument is where Self's position actually matters —
  with Self wrongly at the head, GetItem would receive the interface value as
  its `i`. Oracle: FPC (-Mdelphi), which prints these four lines exactly. }
type
  IBox = interface
    ['{11111111-2222-3333-4444-555555555577}']
    function GetV: Integer;
    procedure SetV(x: Integer);
    function GetItem(i: Integer): Integer;
    property V: Integer read GetV write SetV;
    property Item[i: Integer]: Integer read GetItem;
  end;
  TBox = class(TInterfacedObject, IBox)
  private
    FV: Integer;
  public
    function GetV: Integer;
    procedure SetV(x: Integer);
    function GetItem(i: Integer): Integer;
  end;

function TBox.GetV: Integer;
begin Result := FV; end;

procedure TBox.SetV(x: Integer);
begin FV := x * 10; end;   { *10 so a value that arrived unchanged is visible }

function TBox.GetItem(i: Integer): Integer;
begin Result := FV + i; end;

var i: IBox;
begin
  i := TBox.Create;
  i.SetV(4);
  WriteLn('direct  ', i.GetV);      { control: the arm that already worked }
  WriteLn('read    ', i.V);         { property read through the IMT }
  i.V := 7;                         { property write }
  WriteLn('written ', i.V);
  WriteLn('indexed ', i.Item[3]);   { index arg, so Self's position matters }
end.
