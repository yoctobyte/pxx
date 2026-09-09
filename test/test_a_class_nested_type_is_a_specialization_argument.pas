{ A type declared INSIDE a class, named as a generic argument in that class's
  own scope. fpc compiles and runs every row here; we refused the whole first
  half with `unknown type: PT` and answered the `mixed` row WRONG.

  bug-p-a-class-nested-type-as-a-specialization-argument-resolves-at-unit-scope

  THE `mixed` ROW IS THE ONE THAT MATTERS AND IT IS NOT A COMPILE ERROR. With a
  unit-scope namesake present the refusal became a silent wrong answer: 300
  stored through a `Byte` came back 44, while the source meant the class's own
  Int64. Its readout is deliberately the VALUE and not SizeOf -- both compilers
  answer 8 for the size, because the probe casts to the type it is asking about
  and reports the CAST's view. A size row here would have printed parity on the
  one row where the two compilers disagree completely.

  `plainuse` is the positive control that makes the rest an argument rather than
  a list of passes: the SAME nested name, one line away, in an ordinary type
  position, resolved correctly the whole time. So the compiler always knew which
  type was meant and the specialization did not ask. }
program test_a_class_nested_type_is_a_specialization_argument;
{$mode delphi}
type
  TBox<T> = class
    V: T;
    function Size: Integer;
  end;

  { the namesake, a DIFFERENT type, declared BEFORE the class that shadows it }
  TElem = Byte;

  { v5 -- no inheritance, nothing generic but the template }
  TOwn = class
  public type
    PT = ^Integer;
    TAlias = Int64;
  public
    function Boxed: TBox<TAlias>;
    function PlainUse: PT;
  end;

  { v3/v4 -- the nested type comes from a NON-GENERIC ANCESTOR }
  TBase = class
  public type
    TInner = Int64;
  end;
  TDerived = class(TBase)
  public
    function Boxed: TBox<TInner>;
  end;

  { v10 -- the class's own TElem shadows the unit-scope Byte above }
  TShadow = class
  public type
    TElem = Int64;
  public
    function Boxed: TBox<TElem>;
  end;

  { v11 -- the namesake is declared AFTER the class that shadows it }
  TLate = class
  public type
    TAfter = Int64;
  public
    function Boxed: TBox<TAfter>;
  end;
  TAfter = Byte;

function TBox<T>.Size: Integer; begin Result := SizeOf(T); end;

function TOwn.Boxed: TBox<TAlias>;
begin Result := TBox<TAlias>.Create; Result.V := 300; end;
function TOwn.PlainUse: PT; begin Result := nil; end;

function TDerived.Boxed: TBox<TInner>;
begin Result := TBox<TInner>.Create; Result.V := 300; end;

function TShadow.Boxed: TBox<TElem>;
begin Result := TBox<TElem>.Create; Result.V := 300; end;

function TLate.Boxed: TBox<TAfter>;
begin Result := TBox<TAfter>.Create; Result.V := 300; end;

var
  o: TOwn; d: TDerived; s: TShadow; l: TLate;
  bo: TBox<Int64>;
  plain: TBox<TElem>;
begin
  o := TOwn.Create; d := TDerived.Create; s := TShadow.Create; l := TLate.Create;

  bo := TBox<Int64>(o.Boxed);
  WriteLn('own ', bo.Size, ' ', bo.V);

  bo := TBox<Int64>(d.Boxed);
  WriteLn('inherited ', bo.Size, ' ', bo.V);

  { the row that was silently wrong: 44 here, not 300 }
  bo := TBox<Int64>(s.Boxed);
  WriteLn('mixed ', bo.Size, ' ', bo.V);

  bo := TBox<Int64>(l.Boxed);
  WriteLn('late ', bo.Size, ' ', bo.V);

  { the unit-scope namesake is untouched -- the shadowing is local to the class }
  plain := TBox<TElem>.Create;
  plain.V := 44;
  WriteLn('unitscope ', plain.Size, ' ', plain.V);

  { positive control: the same nested name in an ordinary type position }
  WriteLn('plainuse ', Ord(o.PlainUse = nil));
end.
