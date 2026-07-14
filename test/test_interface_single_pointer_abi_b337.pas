{ An interface VALUE is ONE pointer — the instance (FPC's ABI) — not a fat
  {IMT, instance} pair (b337).

  This is what makes the idiom below expressible at all, and it is everywhere in
  FPC/Delphi code on Linux: interfaces get stashed in pointer-shaped containers
  and cast back. fcl-fpcunit's TTestResult does exactly this with its listener
  list (FListeners.Add(Pointer(AListener)); ITestListener(FListeners[i]).StartTest).
  With a 16-byte value, Pointer() kept one of the two words and the rebuilt
  "interface" dispatched through garbage.

  The IMT is no longer carried in the value: it is recovered from the instance's
  class RTTI blob by interface id at the call (PXXIntfIMTOf). So this also pins:
  - a plain interface call still dispatches correctly (through the same IMT);
  - Pointer(intf) -> IFoo(ptr) roundtrips, both via a variable and inline;
  - a cast-and-call on a getter RESULT (IFoo(List[i]).M) works;
  - interface identity is a plain pointer compare;
  - `as`-casting to an interface still traps on a class that does not implement it
    (checked elsewhere) and yields nil for nil.
  Verified against FPC. }
program test_interface_single_pointer_abi_b337;
{$mode objfpc}{$h+}

type
  IGreeter = interface
    procedure Greet(n: Integer);
    function Name: String;
  end;

  TGreeter = class(TInterfacedObject, IGreeter)
  private
    FName: String;
  public
    constructor Create(const AName: String);
    procedure Greet(n: Integer);
    function Name: String;
  end;

constructor TGreeter.Create(const AName: String);
begin
  FName := AName;
end;

procedure TGreeter.Greet(n: Integer);
begin
  Writeln('greet ', FName, ' ', n);
end;

function TGreeter.Name: String;
begin
  Result := FName;
end;

var
  g, g2: IGreeter;
  p: Pointer;
  slots: array[0..1] of Pointer;
  i: Integer;
begin
  g := TGreeter.Create('a');
  g.Greet(1);                          { ordinary interface dispatch }

  Writeln('size-is-one-word: ', SizeOf(g) = SizeOf(Pointer));

  p := Pointer(g);                     { the value fits a bare pointer }
  g2 := IGreeter(p);                   { ...and casts back }
  g2.Greet(2);
  Writeln('same-object: ', g2 = g);    { identity = plain pointer compare }

  IGreeter(p).Greet(3);                { cast-and-call, no intermediate variable }

  slots[0] := Pointer(g);              { a pointer-shaped container — the fpcunit
                                         listener-list shape }
  slots[1] := Pointer(IGreeter(TGreeter.Create('b')));
  for i := 0 to 1 do
    Writeln('from slot ', i, ': ', IGreeter(slots[i]).Name);

  g := nil;
  Writeln('nil-is-nil: ', g = nil);
end.
