program test_generic_method_unused_is_erased;
{$mode objfpc}
{ A generic method nothing asks for must emit nothing AND leave nothing behind.
  ExpandGenericMethod used to Exit when no use site named a type argument, which
  left `generic function Add<T>` in the token stream for the class-body parser
  to choke on -- so declaring a generic method you do not call was a hard parse
  error, in a unit and in a program alike.

  Every row here is a NEIGHBOUR test as much as an erase test: the erase spans
  two ranges in two sections (the declaration inside the class body, the
  definition in the implementation), and removing one token too many or too few
  takes an ordinary member with it. }
uses ugmun, ugmund;
type
  TInFile = class
    function Before: Integer;
    generic function Unused<T>(a, b: T): T;
    generic function Used<T>(a, b: T): T;
    function After: Integer;
  end;
  TCls = class
    class generic function NeverCls<T>(a: T): T;
    function Plain: Integer;
  end;
function TInFile.Before: Integer;
begin Result := 1; end;
generic function TInFile.Unused<T>(a, b: T): T;
begin Result := a - b; end;
generic function TInFile.Used<T>(a, b: T): T;
begin Result := a + b; end;
function TInFile.After: Integer;
begin Result := 2; end;
class generic function TCls.NeverCls<T>(a: T): T;
begin Result := a; end;
function TCls.Plain: Integer;
begin Result := 42; end;
var
  f: TInFile; c: TCls; bu: TBoxU; bd: TBoxD;
begin
  f := TInFile.Create; c := TCls.Create;
  bu := TBoxU.Create; bd := TBoxD.Create;
  { members on either side of an erased declaration, and of its definition }
  WriteLn(f.Before, ' ', f.After);
  { a USED generic method in the same class as an unused one still expands }
  WriteLn(f.specialize Used<Integer>(7, 3));
  { `class generic`, unused -- the erase must start at `class`, not at `generic` }
  WriteLn(c.Plain);
  { both surfaces, across a uses clause, with zero uses anywhere }
  WriteLn(bu.Tag, ' ', bd.Tag);
end.
