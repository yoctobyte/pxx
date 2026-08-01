unit kwarg_overload_unit;

{ bug-nilpy-keyword-arg-vs-overload-set: a NilPy keyword argument used to
  resolve against the ONE overload the call site had already picked (the
  first one FindProc/FindUMeth found), not the overload SET -- so a keyword
  naming a parameter that only a SIBLING arity declares failed with "has no
  parameter named", even though the call is unambiguous once the keyword
  is allowed to steer overload selection itself.

  Two shapes, mirroring the two real repros: a free/unit-qualified proc
  (html.escape) and a class method (the tkinter configure() facade). }

interface

type
  TThing = class
    procedure paint(const opts: AnsiString); overload;
    procedure paint(const color: AnsiString = ''; width: Integer = -1); overload;
  end;

function render(const s: AnsiString): AnsiString; overload;
function render(const s: AnsiString; loud: Boolean): AnsiString; overload;

implementation

uses sysutils;

procedure TThing.paint(const opts: AnsiString);
begin
  WriteLn('raw: ', opts);
end;

procedure TThing.paint(const color: AnsiString; width: Integer);
begin
  WriteLn('named color=', color, ' width=', width);
end;

function render(const s: AnsiString): AnsiString;
begin
  Result := s;
end;

function render(const s: AnsiString; loud: Boolean): AnsiString;
begin
  if loud then Result := UpperCase(s) else Result := s;
end;

end.
