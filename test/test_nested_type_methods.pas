program test_nested_type_methods;
{ A type declared INSIDE a class body, with its method bodies written in the
  implementation as `TOuter.TInner.Method`. Both arms: a nested CLASS and a
  nested RECORD. The record arm is the one that was broken — the class branch of
  the type-section parser registered the nested name under its qualified spelling
  and told the enclosing class about it, the record branch did neither, so
  `function TOuter.TInner.M` parsed when TInner was a class and failed when it
  was a record. rtl-generics' TComparerService.TInstance is a nested record.
  Delphi mode because a record with methods needs advanced records. }
{$mode delphi}{$H+}

type
  TOuter = class
  public
    type
      TInnerRec = record
        v: Integer;
        function Twice: Integer;
        class function Make(x: Integer): TInnerRec; static;
      end;
      TInnerCls = class
        w: Integer;
        function Thrice: Integer;
      end;
    function UseRec: Integer;
  end;

function TOuter.TInnerRec.Twice: Integer;
begin
  Result := v * 2;
end;

class function TOuter.TInnerRec.Make(x: Integer): TInnerRec;
begin
  Result.v := x;
end;

function TOuter.TInnerCls.Thrice: Integer;
begin
  Result := w * 3;
end;

function TOuter.UseRec: Integer;
var r: TInnerRec;
begin
  r := TInnerRec.Make(5);
  Result := r.Twice;
end;

var
  o: TOuter;
  r: TOuter.TInnerRec;
  c: TOuter.TInnerCls;
begin
  r := TOuter.TInnerRec.Make(21);
  c := TOuter.TInnerCls.Create;
  c.w := 4;
  o := TOuter.Create;
  WriteLn('nested ', r.Twice, ' ', c.Thrice, ' ', o.UseRec);
  o.Free;
  c.Free;
  WriteLn('NESTED TYPE METHODS OK');
end.
