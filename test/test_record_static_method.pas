program test_record_static_method;
{ A record's `class function ... static` invoked on the TYPE name. The parser
  arm that claims `TRec.Something(...)` was written for a record CONSTRUCTOR: it
  allocates a temp receiver, types the call tyRecord and yields the temp. That is
  right for `TPt.Create(7,8)` and wrong for every static — which returns its own
  type and has no receiver at all — so `TRec.MakeI(5)` read an untouched temp and
  returned GARBAGE, with no diagnostic, for any return type. It was fixed for a
  TYPE HELPER's static only, keyed on helper-ness rather than on `static`, so the
  plain-record arm stayed broken. Covered here: the ctor shape the arm exists
  for, a static returning a scalar, and a static returning the record itself
  (rtl-generics' TComparerService factory shape). The helper arm is NOT here —
  FPC refuses `THelper.Static` ("class helpers cannot be used as types"), so it
  has no oracle; it keeps its own coverage. }
{$mode delphi}{$H+}

type
  TPt = record
    x, y: Integer;
    constructor Create(ax, ay: Integer);
    function Sum: Integer;
    class function MakeI(v: Integer): Integer; static;
    class function MakeR(v: Integer): TPt; static;
  end;

constructor TPt.Create(ax, ay: Integer);
begin
  x := ax; y := ay;
end;

function TPt.Sum: Integer;
begin
  Result := x + y;
end;

class function TPt.MakeI(v: Integer): Integer;
begin
  Result := v + 1;
end;

class function TPt.MakeR(v: Integer): TPt;
begin
  Result.x := v;
  Result.y := v * 2;
end;

var
  p: TPt;
begin
  p := TPt.Create(7, 8);
  WriteLn('ctor ', p.Sum);
  WriteLn('static-int ', TPt.MakeI(5));
  p := TPt.MakeR(6);
  WriteLn('static-rec ', p.x, ' ', p.y);
  WriteLn('RECORD STATIC OK');
end.
