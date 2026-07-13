{ A PARENTHESISED expression keeps its class identity: `(b as T)[i]` and `(b as T).ClassName`.

  fcl-json's own suite writes `(Data as TJSONArray)[0].ClassType`. Two symptoms, one cause:

    (b as T)[i]        built a raw AN_INDEX instead of dispatching the DEFAULT PROPERTY,
                       which left the as-cast with no address to take -- "IR_UNSUPPORTED:
                       could not lower AST node (kind 57)".
    (b as T).Member    silently DROPPED an unresolvable member and evaluated to the object
                       POINTER: it printed a NUMBER where a class name was expected, with no
                       error at all.

  ResolveNodeRec has always known an as-cast's class. The parenthesised-expression tail in
  ParseFactor simply never asked -- it was the THIRD copy of member/index dispatch, alongside
  ParseLValueAST's suffix loop and ParseClassRecordSelectors. The duplication WAS the bug, so
  the tail now hands off rather than growing a fourth copy, and the chained loop learned the
  default-property dispatch it was missing. Properties, virtual methods and the
  class-reference ops all come along, and cannot drift apart again. }
program test_paren_expr_class_b297;

type
  TB = class
    N: Integer;
  end;
  TArr = class(TB)
  private
    FL: array[0..2] of TB;
    function GetItem(i: Integer): TB;
  public
    property Items[i: Integer]: TB read GetItem; default;
    procedure Fill;
  end;

function TArr.GetItem(i: Integer): TB;
begin
  Result := FL[i];
end;

procedure TArr.Fill;
var i: Integer;
begin
  for i := 0 to 2 do
  begin
    FL[i] := TB.Create;
    FL[i].N := (i + 1) * 10;
  end;
end;

var
  b: TB;
  a: TArr;
begin
  a := TArr.Create;
  a.Fill;
  b := a;                                     { static type TB, runtime class TArr }

  writeln('direct index   : ', a[1].N);
  writeln('as-cast index  : ', (b as TArr)[1].N);
  writeln('as-cast chained: ', (b as TArr)[2].ClassName);
  writeln('as-cast member : ', (b as TArr).ClassName);
  writeln('as-cast inherit: ', (b as TArr).InheritsFrom(TB));
end.
