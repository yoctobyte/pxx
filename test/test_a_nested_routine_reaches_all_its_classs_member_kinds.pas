{ A nested routine that captures enclosing state is lifted to top level, and
  the free-variable scan rewrites its implicit member references to go through
  a hidden `__nestself`. That scan asked TWO questions -- is this a field, is
  this a method -- so a nested routine reading a PROPERTY or a CLASS VAR of its
  own class answered `undefined variable`, with a working field reference on
  the line above it. fcl-passrc pscanner.pp's HandleMode.SetMode reads six
  properties and every one was a wall.

  The rows are the member KINDS, enumerated from the concept rather than from
  the report: field, method, class var, class const, property-read (through a
  getter), property-read (straight off a field), property-WRITE. Each asserts a
  VALUE that only the right receiver can produce -- the getter multiplies by ten
  and the write goes through a setter, so a reference that resolved to the wrong
  storage prints a different number rather than failing to build.

  THE CLASS CONST ROW ARRIVED SECOND AND THAT IS THE INTERESTING PART. It was
  deliberately absent while `<instance>.K` was refused across pxx's member
  dispatch generally -- `TC.K` worked and `c.K` did not, with no nested routine
  involved -- because the desugar here is a `__nestself.` prefix, so adding the
  kind would have turned `undefined variable (K)` into `"K": no such member`:
  a different wrong answer, not a fix. The receiver bug is fixed now and the
  scan asks about the fifth kind. The absence was measured, not overlooked,
  which is why it could be removed the day its blocker closed.
  bug-p-a-nested-routine-sees-only-two-of-its-classs-five-member-kinds
  bug-p-a-class-const-is-unreachable-through-an-instance-receiver }
{$mode objfpc}
program test_a_nested_routine_reaches_all_its_classs_member_kinds;
type
  TC = class
  private
    FV: Integer;
    function GetV: Integer;
    procedure SetV(a: Integer);
  public
    const K = 5;
    class var CV: Integer;
    property V: Integer read GetV write SetV;
    property RO: Integer read FV;
    function Meth(a: Integer): Integer;
    procedure Outer;
  end;
function TC.GetV: Integer; begin Result := FV * 10; end;
procedure TC.SetV(a: Integer); begin FV := a; end;
function TC.Meth(a: Integer): Integer; begin Result := a + FV; end;
procedure TC.Outer;
  procedure Inner(n: Integer);
  begin
    WriteLn('field=', FV);
    WriteLn('meth=', Meth(1));
    WriteLn('classvar=', CV);
    WriteLn('propread=', V);
    WriteLn('propro=', RO);
    V := n;
    WriteLn('propwrite=', V);
    WriteLn('classconst=', K);
  end;
begin
  FV := 3; CV := 9;
  Inner(7);
end;
var c: TC;
begin c := TC.Create; c.Outer; end.
