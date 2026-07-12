program test_method_overload_types_b248;
{ Method and constructor overloads were resolved by NAME + ARITY only, never by
  argument type:
  - a same-arity set always ran the FIRST body, so P('xy') silently executed
    P(Integer) and printed the string's address (bug-pascal-method-overload-
    ignores-arg-types);
  - the ctor target was re-resolved inside every BACKEND with a first-Create-by-
    name match, so TA.Create('zed') either died with "too many arguments" or ran
    the wrong ctor (bug-pascal-ctor-overload-first-match).
  A Char argument is compatible with BOTH Integer (ordinal) and string, so the
  choice is ranked, not first-match: char -> string wins, as in FPC. }
type
  TA = class
    tag: string;
    constructor Create; overload;
    constructor Create(AName: string); overload;
    constructor Create(N: Integer); overload;
    procedure P(a: Integer); overload;
    procedure P(a: string); overload;
    function Twice(a: Integer): Integer; overload;
    function Twice(a: string): string; overload;
  end;

  TSub = class(TA)
  end;

constructor TA.Create;                begin tag := 'none'; end;
constructor TA.Create(AName: string); begin tag := 'str:' + AName; end;
constructor TA.Create(N: Integer);    begin tag := 'int'; end;

procedure TA.P(a: Integer); begin writeln('int ', a); end;
procedure TA.P(a: string);  begin writeln('str ', a); end;

function TA.Twice(a: Integer): Integer; begin Twice := a * 2; end;
function TA.Twice(a: string): string;   begin Twice := a + a; end;

var
  o: TA;
  s: TSub;
begin
  o := TA.Create;
  writeln('ctor=', o.tag);
  o.P(1);
  o.P('xy');
  o.P('x');                  { Char literal must prefer the string overload }
  writeln('twice-int=', o.Twice(21));
  writeln('twice-str=', o.Twice('ab'));
  o.Free;

  o := TA.Create('zed');
  writeln('ctor=', o.tag);
  o.Free;

  o := TA.Create(42);
  writeln('ctor=', o.tag);
  o.Free;

  { overloads resolve through an inherited method set too }
  s := TSub.Create('sub');
  writeln('sub-ctor=', s.tag);
  s.P('hi');
  s.P(7);
  s.Free;
end.
